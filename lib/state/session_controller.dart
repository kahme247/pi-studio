import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../git/git_ops.dart';
import '../pi/pi_client.dart';

enum ItemKind { user, assistant, thinking, tool, notice, event }

class ChatItem {
  ChatItem(this.kind, {this.text = ''});

  final ItemKind kind;
  String text;

  DateTime? time;
  int? thinkingSeconds;
  bool animated = false;

  String toolName = '';
  String toolCallId = '';
  String? args;
  String? result;
  bool isError = false;
  bool isDone = false;

  /// Stable across history re-renders (which rebuild every object): lets the
  /// transcript keep element identity when older pages prepend, instead of
  /// rematching every visible row by index and relaying out the whole list.
  /// Null for live-streamed items, which keep object identity instead.
  String? stableId;
}

/// Owns one `pi --mode rpc` process and its transcript. Sessions are
/// independent: switching between them in the UI never interrupts a turn.
class SessionController extends ChangeNotifier {
  SessionController({
    required this.projectDir,
    this.worktreeBranch,
    this.fallbackTitle,
    this.sourcePath,
  });

  String projectDir;

  /// Set when this session runs in a git worktree created for it.
  final String? worktreeBranch;

  /// Display title for resumed sessions whose pi name is unset (pi names are
  /// optional; the file's first message is the usual fallback).
  String? fallbackTitle;

  /// Session file this controller was opened from, recorded before the
  /// process starts so repeat clicks can find it.
  final String? sourcePath;

  /// Windows-style, case-insensitive path comparison.
  static String normalizePath(String path) =>
      path.replaceAll('/', r'\').replaceAll(RegExp(r'\\+$'), '').toLowerCase();

  bool matchesSession(String path) {
    final normalized = normalizePath(path);
    final from = sourcePath;
    if (from != null && normalizePath(from) == normalized) return true;
    final file = sessionFile;
    return file != null && normalizePath(file) == normalized;
  }

  final List<ChatItem> items = [];
  final Map<String, ChatItem> toolItems = {};
  ChatItem? streamingAssistant;
  ChatItem? streamingThinking;

  var connected = false;
  var streaming = false;
  var loading = false;
  var unread = false;
  var status = 'New session';
  String? sessionFile;
  String? sessionName;
  String? modelName;
  String? thinkingLevel;
  String? gitBranch;
  List<String> gitBranches = [];
  int diffAdditions = 0;
  int diffDeletions = 0;
  bool hasDiffStats = false;
  bool fullAccess = true;

  void toggleAccess() {
    fullAccess = !fullAccess;
    _notify();
  }

  /// A session can't change project once it has conversation history.
  bool get hasStarted => items.any((item) => item.kind == ItemKind.user);

  /// True once the pi process exists (spawned on first send or on resume).
  bool get isStarted => _client != null;

  /// Retargets a session that hasn't been used yet: pi restarts in the new
  /// folder (the old empty session file is removed) so the UI can keep model
  /// selection etc. without spawning a second session.
  Future<void> setProject(String dir) async {
    if (hasStarted) return;
    final abandonedFile = sessionFile;
    projectDir = dir;
    fallbackTitle = null;
    sessionName = null;
    sessionFile = null;
    await _teardownProcess();
    if (abandonedFile != null) {
      try {
        final file = File(abandonedFile);
        if (file.existsSync()) await file.delete();
      } on FileSystemException {
        // Best effort; an empty leftover file is harmless.
      }
    }
    await connect();
    _notify();
  }

  List<Map<String, dynamic>> models = [];
  List<String> thinkingLevels = [];
  Map<String, dynamic>? stats;

  final List<String> stderrTail = [];
  DateTime? _thinkingStartedAt;
  DateTime? _turnStartedAt;
  Timer? _notifyThrottle;
  Timer? _turnTicker;
  int _outputTokens = 0;

  /// Throughput of the current turn, for the "Processing … token/s" header.
  double? tokensPerSecond;

  int get processingSeconds {
    final started = _turnStartedAt;
    return started == null ? 0 : DateTime.now().difference(started).inSeconds;
  }

  PiClient? _client;
  StreamSubscription<Map<String, dynamic>>? _eventsSub;
  StreamSubscription<String>? _stderrSub;
  var _disposed = false;

  String get title {
    final name = sessionName;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    final fallback = fallbackTitle;
    if (fallback != null && fallback.trim().isNotEmpty) return fallback.trim();
    for (final item in items) {
      if (item.kind == ItemKind.user && item.text.trim().isNotEmpty) {
        final text = item.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        return text.length <= 42 ? text : '${text.substring(0, 42)}…';
      }
    }
    return 'New session';
  }

  Future<void> connect({String? resumePath}) async {
    if (loading || _disposed) return;
    loading = true;
    notifyListeners();
    try {
      await _teardownProcess();
      final client = PiClient(workingDirectory: projectDir);
      try {
        await client.start();
      } catch (error) {
        _notice('$error');
        status = 'Not connected';
        await client.dispose();
        return;
      }
      _client = client;
      stderrTail.clear();
      _eventsSub = client.events.listen(_onEvent);
      _stderrSub = client.stderr.listen((line) {
        debugPrint('[pi] $line');
        stderrTail.add(line.trim());
        if (stderrTail.length > 20) stderrTail.removeAt(0);
      });
      connected = true;
      status = 'Starting…';

      if (resumePath != null) {
        await client.switchSession(resumePath);
        sessionFile = resumePath;
        // Transcript and backend state are independent: fetch both at once
        // and paint the transcript the moment it arrives, so the skeleton
        // clears before the slower state/stats calls finish.
        final messagesFuture = client.getMessages();
        final stateFuture = client.getState();
        _setHistory(await messagesFuture);
        loading = false;
        _notify();
        _applyState(await stateFuture);
        status = 'Resumed';
      } else {
        items.clear();
        toolItems.clear();
        streamingAssistant = null;
        streamingThinking = null;
        await _refreshState();
        status = 'Ready';
      }
      unawaited(loadCapabilities());
      unawaited(refreshStats());
      unawaited(loadGitInfo());
      unawaited(loadDiffStats());
    } catch (error) {
      _notice('Session init failed: $error');
      status = 'Not connected';
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> _refreshState() async {
    final response = await _client?.getState();
    _applyState(response);
  }

  void _applyState(Map<String, dynamic>? response) {
    final data = response?['data'];
    if (data is Map) {
      sessionFile = data['sessionFile'] as String?;
      sessionName = data['sessionName'] as String?;
      final model = data['model'];
      if (model is Map && model['name'] is String) {
        modelName = model['name'] as String;
      }
      if (data['thinkingLevel'] is String) {
        thinkingLevel = data['thinkingLevel'] as String;
      }
    }
  }

  /// Loads the model list and thinking levels for the composer menus.
  /// Best-effort: older pi builds may not support these commands.
  /// Branch shown in the composer footer: the worktree's branch when this
  /// session runs in one, otherwise the repo's current branch.
  String? get branchLabel => worktreeBranch ?? gitBranch;

  Future<void> loadGitInfo() async {
    try {
      gitBranch = await currentBranch(projectDir);
      gitBranches = await localBranches(projectDir);
    } catch (_) {
      gitBranch = null;
      gitBranches = [];
    }
    _notify();
  }

  /// Uncommitted diff size, shown as +added/-removed in the chat header.
  Future<void> loadDiffStats() async {
    try {
      final stats = await diffStats(projectDir);
      if (stats != null) {
        diffAdditions = stats.additions;
        diffDeletions = stats.deletions;
        hasDiffStats = true;
      }
    } catch (_) {
      // Not a repo or git missing; keep the header clean.
    }
    _notify();
  }

  Future<void> loadCapabilities() async {
    final client = _client;
    if (client == null) return;
    try {
      final modelsResponse = await client.getAvailableModels();
      final modelsData = modelsResponse['data'];
      if (modelsData is Map && modelsData['models'] is List) {
        models = (modelsData['models'] as List)
            .whereType<Map>()
            .map((model) => Map<String, dynamic>.from(model))
            .toList();
      }
      final levelsResponse = await client.getAvailableThinkingLevels();
      final levelsData = levelsResponse['data'];
      if (levelsData is Map && levelsData['levels'] is List) {
        thinkingLevels = (levelsData['levels'] as List)
            .whereType<String>()
            .toList();
      }
    } catch (_) {
      // Composer menus stay empty; everything else keeps working.
    }
    _notify();
  }

  Future<void> setModel(String provider, String modelId) async {
    final response = await _client?.setModel(provider, modelId);
    final data = response?['data'];
    if (data is Map) {
      modelName = data['name'] as String? ?? modelId;
    }
    _notify();
    // Reasoning levels are model-specific: refresh them for the new model.
    unawaited(loadCapabilities());
  }

  Future<void> setThinkingLevel(String level) async {
    await _client?.setThinkingLevel(level);
    thinkingLevel = level;
    _notify();
  }

  /// Token/cost/context stats for the context ring and its detail popup.
  /// Best-effort: failures leave the previous snapshot in place.
  Future<void> refreshStats() async {
    final client = _client;
    if (client == null) return;
    try {
      final response = await client.getSessionStats();
      final data = response['data'];
      if (data is Map) stats = Map<String, dynamic>.from(data);
    } catch (_) {
      // Ignore; the ring just keeps its last value.
    }
    _notify();
  }

  Future<void> newSession() async {
    final client = _client;
    if (client == null || !connected) {
      // Pending session: just reset the draft.
      items.clear();
      toolItems.clear();
      _history = [];
      _historyWindow = _pageSize;
      streamingAssistant = null;
      streamingThinking = null;
      sessionName = null;
      fallbackTitle = null;
      status = 'New session';
      _notify();
      return;
    }
    await client.newSession();
    items.clear();
    toolItems.clear();
    _history = [];
    _historyWindow = _pageSize;
    streamingAssistant = null;
    streamingThinking = null;
    sessionName = null;
    fallbackTitle = null;
    await _refreshState();
    status = 'New session';
    _notify();
  }

  Future<void> send(String text) async {
    final message = text.trim();
    if (message.isEmpty) return;
    // Lazily start pi on the first message: a pending session has no process
    // and no session file until then.
    if (!isStarted) {
      await connect();
    }
    final client = _client;
    if (client == null || !connected) return;
    if (streaming) {
      await client.steer(message);
      _notice('Queued (steer): $message');
    } else {
      // pi echoes the user message via message_start; deduped there.
      items.add(ChatItem(ItemKind.user, text: message));
      await client.prompt(message);
    }
    _notify();
  }

  Future<void> abort() async => _client?.abort();

  Future<void> rename(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _client?.setSessionName(trimmed);
    sessionName = trimmed;
    _notify();
  }

  void _setHistory(List<dynamic> messages) {
    _history = messages
        .whereType<Map>()
        .map((message) => Map<String, dynamic>.from(message))
        .toList();
    _historyWindow = _history.length > _pageSize ? _pageSize : _history.length;
    _renderHistory();
  }

  static const _pageSize = 400;
  List<Map<String, dynamic>> _history = [];
  var _historyWindow = _pageSize;

  bool get hasHiddenHistory => _history.length > _historyWindow;
  int get hiddenHistoryCount => _history.length - _historyWindow;

  /// Reveals hidden history in bounded pages — called when the user scrolls
  /// to the top of the transcript. Unbounded chunks (a quarter of thousands
  /// of rows) never finish laying out before the scroll compensation runs,
  /// so the view drops; 100 rows settle within a frame or two.
  void loadOlderHistory() {
    if (!hasHiddenHistory) return;
    var step = (hiddenHistoryCount / 4).ceil().clamp(1, hiddenHistoryCount);
    if (step > 100) step = 100;
    _historyWindow += step;
    _renderHistory();
    _notify();
  }

  void _renderHistory() {
    final start = _history.length > _historyWindow
        ? _history.length - _historyWindow
        : 0;
    items.clear();
    toolItems.clear();
    if (start > 0) {
      items.add(
        ChatItem(ItemKind.notice)
          ..text = '$start earlier messages hidden — scroll up to load'
          ..stableId = 'notice',
      );
    }
    final window = _history.sublist(start);
    for (var i = 0; i < window.length; i++) {
      _addStoredMessage(window[i], stableId: '${start + i}');
    }
  }

  void _addStoredMessage(Map<String, dynamic> message, {String? stableId}) {
    final role = message['role'];
    final time = _msToDate(message['timestamp']);
    var block = 0;
    String? nextId() => stableId == null ? null : '$stableId:${block++}';
    if (role == 'user') {
      items.add(
        ChatItem(ItemKind.user, text: _contentToText(message['content']))
          ..time = time
          ..stableId = nextId(),
      );
    } else if (role == 'assistant') {
      final blocks = message['content'];
      if (blocks is! List) return;
      for (final block in blocks) {
        if (block is! Map) continue;
        switch (block['type']) {
          case 'text':
            final text = '${block['text'] ?? ''}';
            if (text.trim().isNotEmpty) {
              items.add(
                ChatItem(ItemKind.assistant, text: text)
                  ..time = time
                  ..stableId = nextId(),
              );
            }
          case 'thinking':
            items.add(
              ChatItem(ItemKind.thinking, text: '${block['thinking'] ?? ''}')
                ..time = time
                ..stableId = nextId(),
            );
          case 'toolCall':
            final item = ChatItem(ItemKind.tool)
              ..toolName = '${block['name'] ?? 'tool'}'
              ..toolCallId = '${block['id'] ?? ''}'
              ..args = _prettyJson(block['arguments'])
              ..stableId = nextId()
              ..isDone = true;
            if (item.toolCallId.isNotEmpty) toolItems[item.toolCallId] = item;
            items.add(item);
        }
      }
    } else if (role == 'toolResult') {
      final item = toolItems['${message['toolCallId']}'];
      if (item != null) {
        item.result = _contentToText(message['content']);
        item.isError = message['isError'] == true;
      }
    }
  }

  // ---------------------------------------------------------------- events

  void _onEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'agent_start':
        streaming = true;
        _turnStartedAt = DateTime.now();
        _outputTokens = 0;
        tokensPerSecond = null;
        _turnTicker?.cancel();
        _turnTicker = Timer.periodic(const Duration(seconds: 1), (_) {
          _updateTokensPerSecond();
          _notify();
        });
      case 'agent_settled':
        streaming = false;
        unread = true;
        _turnTicker?.cancel();
        _turnTicker = null;
        unawaited(refreshStats());
        unawaited(loadDiffStats());
      case 'message_start':
        _onMessageStart(event['message']);
      case 'message_update':
        _onMessageUpdate(event);
      case 'message_end':
        _onMessageEnd(event['message']);
      case 'tool_execution_start':
        _onToolStart(event);
      case 'tool_execution_update':
        _onToolProgress(event);
      case 'tool_execution_end':
        _onToolEnd(event);
      case 'extension_ui_request':
        _onExtensionUi(event);
      case 'pi_exit':
        connected = false;
        streaming = false;
        status = 'pi exited (code ${event['code']})';
        if (stderrTail.isNotEmpty) {
          items.add(
            ChatItem(ItemKind.notice)
              ..text = 'pi said: ${stderrTail.join(' | ')}',
          );
        }
      case 'compaction_end':
        final aborted = event['aborted'] == true;
        items.add(
          ChatItem(ItemKind.event)
            ..text = aborted ? 'Compaction aborted' : 'Context compacted',
        );
    }
    if (event['type'] == 'message_update' ||
        event['type'] == 'tool_execution_update') {
      _notifyThrottled();
    } else {
      _notify();
    }
  }

  void _onMessageStart(Object? raw) {
    if (raw is! Map) return;
    final message = Map<String, dynamic>.from(raw);
    final role = message['role'];
    final text = _contentToText(message['content']);
    if (role == 'user') {
      if (items.isNotEmpty &&
          items.last.kind == ItemKind.user &&
          items.last.text == text) {
        return; // echo of the bubble we added locally
      }
      items.add(ChatItem(ItemKind.user, text: text));
    } else if (role == 'assistant') {
      // The assistant bubble is created lazily on the first text delta: a
      // tool-only turn must not leave an empty item behind, because empty
      // items split one activity run into several blocks.
      streamingAssistant = null;
      streamingThinking = null;
    }
  }

  void _onMessageUpdate(Map<String, dynamic> event) {
    final usage = event['usage'];
    if (usage is Map && usage['output'] is num) {
      _outputTokens = (usage['output'] as num).round();
      _updateTokensPerSecond();
    }
    final rawDelta = event['assistantMessageEvent'];
    if (rawDelta is! Map) return;
    final delta = Map<String, dynamic>.from(rawDelta);
    final text = delta['delta'] as String? ?? '';
    switch (delta['type']) {
      case 'text_start':
        _ensureAssistant();
      case 'text_delta':
        _ensureAssistant().text += text;
      case 'thinking_start':
        _thinkingStartedAt = DateTime.now();
        streamingThinking = ChatItem(ItemKind.thinking);
        items.add(streamingThinking!);
      case 'thinking_delta':
        streamingThinking?.text += text;
      case 'thinking_end':
        final started = _thinkingStartedAt;
        if (started != null && streamingThinking != null) {
          streamingThinking!.thinkingSeconds = DateTime.now()
              .difference(started)
              .inSeconds;
        }
        _thinkingStartedAt = null;
      case 'toolcall_start':
        final item = ChatItem(ItemKind.tool)
          ..toolName = '${delta['toolName'] ?? 'tool'}'
          ..toolCallId = '${delta['id'] ?? ''}';
        if (item.toolCallId.isNotEmpty) toolItems[item.toolCallId] = item;
        items.add(item);
      case 'toolcall_delta':
        final item = _lastOpenToolItem();
        item?.args = (item.args ?? '') + text;
      case 'toolcall_end':
        final item = _lastOpenToolItem();
        final call = delta['toolCall'];
        if (item != null && call is Map) {
          item.args = _prettyJson(call['arguments']);
          final id = '${call['id'] ?? ''}';
          if (id.isNotEmpty && id != item.toolCallId) {
            toolItems.remove(item.toolCallId);
            item.toolCallId = id;
            toolItems[id] = item;
          }
        }
    }
  }

  void _onMessageEnd(Object? raw) {
    if (raw is! Map) return;
    final message = Map<String, dynamic>.from(raw);
    if (message['role'] != 'assistant') return;
    final item = streamingAssistant;
    final blocks = message['content'];
    if (item != null) {
      if (item.text.trim().isEmpty && blocks is List) {
        item.text = blocks
            .whereType<Map>()
            .where((block) => block['type'] == 'text')
            .map((block) => '${block['text'] ?? ''}')
            .join();
      }
      if (item.text.trim().isEmpty) {
        // Tool-only message: drop the empty bubble so the surrounding steps
        // stay in one activity block.
        items.remove(item);
      }
    }
    streamingAssistant = null;
    streamingThinking = null;
  }

  void _onToolStart(Map<String, dynamic> event) {
    final id = '${event['toolCallId'] ?? ''}';
    var item = toolItems[id];
    if (item == null) {
      // Older pi builds omit the id on toolcall_start; adopt the open item.
      item = _lastOpenToolItem();
      if (item != null) {
        toolItems.remove(item.toolCallId);
        item
          ..toolCallId = id
          ..toolName = '${event['toolName'] ?? item.toolName}';
        if (id.isNotEmpty) toolItems[id] = item;
      }
    }
    if (item != null && event['args'] != null) {
      item.args = _prettyJson(event['args']);
    }
  }

  void _onToolProgress(Map<String, dynamic> event) {
    final item = toolItems['${event['toolCallId']}'];
    final partial = event['partialResult'];
    if (item != null && partial is Map) {
      item.result = _contentToText(partial['content']);
    }
  }

  void _onToolEnd(Map<String, dynamic> event) {
    final item = toolItems['${event['toolCallId']}'];
    if (item == null) return;
    final result = event['result'];
    if (result is Map) item.result = _contentToText(result['content']);
    item
      ..isError = event['isError'] == true
      ..isDone = true;
  }

  void _onExtensionUi(Map<String, dynamic> event) {
    final method = '${event['method']}';
    if (const {'select', 'confirm', 'input', 'editor'}.contains(method)) {
      // No dialog UI yet; decline so the agent never blocks on us.
      _client?.declineExtensionUi('${event['id']}');
      items.add(
        ChatItem(
          ItemKind.notice,
        )..text = 'Extension dialog auto-declined: ${event['title'] ?? method}',
      );
    }
  }

  // --------------------------------------------------------------- helpers

  ChatItem _ensureAssistant() {
    final existing = streamingAssistant;
    if (existing != null) return existing;
    final item = ChatItem(ItemKind.assistant);
    streamingAssistant = item;
    items.add(item);
    return item;
  }

  ChatItem? _lastOpenToolItem() {
    for (var i = items.length - 1; i >= 0; i--) {
      final item = items[i];
      if (item.kind == ItemKind.tool && !item.isDone) return item;
    }
    return null;
  }

  void _updateTokensPerSecond() {
    final started = _turnStartedAt;
    if (started == null) return;
    final millis = DateTime.now().difference(started).inMilliseconds;
    if (millis <= 500 || _outputTokens <= 0) return;
    tokensPerSecond = _outputTokens * 1000 / millis;
  }

  void _notice(String text) =>
      items.add(ChatItem(ItemKind.notice)..text = text);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Coalesces the high-frequency streaming events (token deltas, tool output
  /// chunks) into ~16 updates/second so the UI stays smooth.
  void _notifyThrottled() {
    if (_disposed) return;
    if (_notifyThrottle?.isActive ?? false) return;
    _notifyThrottle = Timer(const Duration(milliseconds: 60), () {
      _notifyThrottle = null;
      _notify();
    });
  }

  Future<void> _teardownProcess() async {
    await _eventsSub?.cancel();
    await _stderrSub?.cancel();
    _eventsSub = null;
    _stderrSub = null;
    await _client?.dispose();
    _client = null;
    connected = false;
    streaming = false;
    streamingAssistant = null;
    streamingThinking = null;
    toolItems.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _turnTicker?.cancel();
    _notifyThrottle?.cancel();
    _eventsSub?.cancel();
    _stderrSub?.cancel();
    _client?.dispose();
    super.dispose();
  }

  static DateTime? _msToDate(Object? value) =>
      value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;

  static String _contentToText(Object? content) {
    if (content == null) return '';
    if (content is String) return content;
    if (content is List) {
      final buffer = StringBuffer();
      for (final block in content) {
        if (block is String) {
          buffer.write(block);
        } else if (block is Map) {
          if (block['type'] == 'text') buffer.write(block['text'] ?? '');
          if (block['type'] == 'image') buffer.write('[image]');
        }
      }
      return buffer.toString();
    }
    return '$content';
  }

  static String _prettyJson(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return '$value';
    }
  }
}
