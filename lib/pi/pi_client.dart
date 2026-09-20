import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Minimal client for `pi --mode rpc`.
///
/// Protocol: https://pi.dev/docs/latest/rpc — strict JSONL over stdin/stdout.
/// LF is the only record delimiter, so we split by hand: generic line readers
/// (Dart's LineSplitter included) must not be used here per the spec.
class PiClient {
  PiClient({required this.workingDirectory});

  final String workingDirectory;

  Process? _process;
  var _closed = false;
  var _nextId = 0;
  var _buffer = '';

  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _stderr = StreamController<String>.broadcast();
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};

  /// Agent events: message_update, tool_execution_*, agent_settled, ...
  Stream<Map<String, dynamic>> get events => _events.stream;

  /// Raw stderr from the pi process (logs, diagnostics).
  Stream<String> get stderr => _stderr.stream;

  bool get isRunning => _process != null && !_closed;

  Future<void> start({String? sessionName}) async {
    if (_process != null) return;
    final args = <String>[
      '--mode',
      'rpc',
      if (sessionName != null && sessionName.trim().isNotEmpty)
        ...['--name', sessionName.trim()],
    ];
    try {
      _process = await Process.start(
        'pi',
        args,
        workingDirectory: workingDirectory,
        // npm installs `pi` as a .cmd shim on Windows.
        runInShell: Platform.isWindows,
      );
    } on ProcessException catch (e) {
      _closed = true;
      throw StateError(
        'Could not start the pi CLI: $e\n'
        'Install it first: npm install -g @earendil-works/pi-coding-agent',
      );
    }
    _process!.stdout.transform(utf8.decoder).listen(_onStdout);
    _process!.stderr.transform(utf8.decoder).listen((chunk) {
      if (!_stderr.isClosed) _stderr.add(chunk);
    });
    unawaited(_process!.exitCode.then((code) {
      _closed = true;
      for (final completer in _pending.values) {
        if (!completer.isCompleted) {
          completer.completeError(StateError('pi exited with code $code'));
        }
      }
      _pending.clear();
      if (!_events.isClosed) _events.add({'type': 'pi_exit', 'code': code});
    }));
  }

  void _onStdout(String chunk) {
    _buffer += chunk;
    while (true) {
      final newline = _buffer.indexOf('\n');
      if (newline == -1) return;
      var line = _buffer.substring(0, newline);
      _buffer = _buffer.substring(newline + 1);
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      if (line.trim().isEmpty) continue;
      _onLine(line);
    }
  }

  void _onLine(String line) {
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map<String, dynamic>) return;
      json = decoded;
    } on FormatException {
      return;
    }
    if (json['type'] == 'response') {
      final id = json['id'] as String?;
      final completer = id == null ? null : _pending.remove(id);
      if (completer != null && !completer.isCompleted) completer.complete(json);
      return;
    }
    if (!_events.isClosed) _events.add(json);
  }

  void _send(Map<String, dynamic> command) {
    final process = _process;
    if (process == null || _closed) return;
    process.stdin.writeln(jsonEncode(command));
  }

  Future<Map<String, dynamic>> _request(
    String type, [
    Map<String, dynamic> extra = const {},
  ]) {
    final id = 'req-${_nextId++}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    _send({'id': id, 'type': type, ...extra});
    return completer.future.timeout(
      const Duration(seconds: 120),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('$type timed out');
      },
    );
  }

  Future<void> prompt(String message) =>
      _request('prompt', {'message': message});

  /// Queue a message while the agent is working (delivered between turns).
  Future<void> steer(String message) =>
      _request('steer', {'message': message});

  /// Queue a message delivered after the agent finishes everything.
  Future<void> followUp(String message) =>
      _request('follow_up', {'message': message});

  Future<void> abort() => _request('abort');

  Future<void> newSession() => _request('new_session');

  Future<Map<String, dynamic>> getState() => _request('get_state');

  Future<List<dynamic>> getMessages() async {
    final response = await _request('get_messages');
    final data = response['data'];
    if (data is Map && data['messages'] is List) {
      return data['messages'] as List<dynamic>;
    }
    return const [];
  }

  Future<void> switchSession(String path) =>
      _request('switch_session', {'sessionPath': path});

  Future<void> setSessionName(String name) =>
      _request('set_session_name', {'name': name});

  Future<Map<String, dynamic>> getSessionStats() =>
      _request('get_session_stats');

  Future<Map<String, dynamic>> getAvailableModels() =>
      _request('get_available_models');

  Future<Map<String, dynamic>> getAvailableThinkingLevels() =>
      _request('get_available_thinking_levels');

  Future<Map<String, dynamic>> setModel(String provider, String modelId) =>
      _request('set_model', {'provider': provider, 'modelId': modelId});

  Future<Map<String, dynamic>> setThinkingLevel(String level) =>
      _request('set_thinking_level', {'level': level});

  /// Auto-decline a blocking extension dialog so the agent never hangs.
  void declineExtensionUi(String id) =>
      _send({'type': 'extension_ui_response', 'id': id, 'cancelled': true});

  Future<void> dispose() async {
    _closed = true;
    final process = _process;
    _process = null;
    // ponytail: kills pi only; if orphaned bash-tool children show up, kill the tree.
    process?.kill();
    await _events.close();
    await _stderr.close();
  }
}
