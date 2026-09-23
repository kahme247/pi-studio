import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:window_manager/window_manager.dart';

import 'git/git_ops.dart';
import 'pi/session_store.dart';
import 'platform/folder_picker.dart';
import 'platform/window_controls.dart';
import 'settings/pi_models.dart';
import 'settings/pi_settings.dart';
import 'settings/settings_page.dart';
import 'state/projects_store.dart';
import 'state/session_controller.dart';
import 'ui/smooth_scroll.dart';
import 'ui/app_theme.dart';
import 'ui/primitives.dart';
import 'ui/review_pane.dart';
import 'ui/session_chrome.dart';
import 'ui/transcript_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Transparent backdrop on Windows only: the Linux runner keeps its opaque
  // GTK frame. The existing Win32 title bar / resize machinery is untouched —
  // window_manager only supplies the transparent frame and clean first show.
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(backgroundColor: Colors.transparent),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  runApp(const PiStudioApp());
}

class PiStudioApp extends StatelessWidget {
  const PiStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pi Studio',
      debugShowCheckedModeBanner: false,
      theme: appTheme(translucent: Platform.isWindows),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<SessionController> _sessions = [];
  final _composer = TextEditingController();
  late final _scroll = SmoothScrollController(
    wheelDuration: () => _wheelDuration,
  );

  /// Wheel-scroll ease; zeroed when the OS asks for reduced motion.
  var _wheelDuration = const Duration(milliseconds: 160);
  final _projectsStore = PathListStore.open('projects.json');
  final _archiveStore = PathListStore.open('archived.json');
  final List<String> _projects = [];
  final List<String> _archived = [];
  var _searching = false;
  var _searchQuery = '';
  String? _lastProjectDir;
  var _showRail = false;
  RailTab _railTab = RailTab.review;
  var _showSettings = false;
  final _piSettings = PiSettings();
  final _piModels = PiModels();
  var _loadingOlder = false;
  var _sidebarWidth = 264.0;
  var _railWidth = 520.0;
  var _composerFocused = false;
  final _searchController = TextEditingController();
  final _branchSearchController = TextEditingController();
  List<PiSession> _savedSessions = [];
  SessionController? _selected;

  @override
  void initState() {
    super.initState();
    _loadSavedSessions();
    _projectsStore.load().then((projects) {
      if (!mounted) return;
      final seen = <String>{};
      setState(() {
        for (final project in projects) {
          if (seen.add(SessionController.normalizePath(project))) {
            _projects.add(project);
          }
        }
      });
    });
    _archiveStore.load().then((paths) {
      if (mounted) setState(() => _archived.addAll(paths));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _wheelDuration = MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 160);
  }

  @override
  void dispose() {
    for (final session in _sessions) {
      session.removeListener(_onControllerChanged);
      session.dispose();
    }
    _composer.dispose();
    _scroll.dispose();
    _searchController.dispose();
    _branchSearchController.dispose();
    _piSettings.dispose();
    _piModels.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- sessions

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    _scrollToEnd();
  }

  Future<void> _loadSavedSessions() async {
    final sessions = await listSessions();
    if (!mounted) return;
    setState(() => _savedSessions = sessions);
  }

  /// Saved sessions that belong to this project folder (by recorded cwd),
  /// excluding ones that are already open in the sidebar.
  /// Flat session list: live sessions and saved ones merged, newest first,
  /// grouped by age ("Today", "This Week", …).
  List<Widget> _sessionList(BuildContext context) {
    final theme = Theme.of(context);
    final query = _searchQuery.trim().toLowerCase();
    bool matches(String title, String folder) =>
        query.isEmpty ||
        title.toLowerCase().contains(query) ||
        folder.toLowerCase().contains(query);

    final archivedPaths = _archived
        .map(SessionController.normalizePath)
        .toSet();
    final openByPath = <String, SessionController>{};
    for (final session in _sessions) {
      final path = session.sourcePath ?? session.sessionFile;
      if (path != null) {
        openByPath[SessionController.normalizePath(path)] = session;
      }
    }

    final entries = <({DateTime time, Widget widget})>[];
    final usedOpen = <SessionController>{};
    for (final saved in _savedSessions) {
      if (archivedPaths.contains(SessionController.normalizePath(saved.path))) {
        continue;
      }
      final open = openByPath[SessionController.normalizePath(saved.path)];
      final folder = _folderName(saved.cwd ?? '');
      if (open != null) {
        usedOpen.add(open);
        if (matches(open.title, folder)) {
          entries.add((
            time: saved.modified,
            widget: _sessionCard(context, open, saved.modified),
          ));
        }
      } else if (matches(saved.title, folder)) {
        entries.add((time: saved.modified, widget: _savedCard(context, saved)));
      }
    }
    for (final session in _sessions) {
      if (usedOpen.contains(session)) continue;
      final folder = _folderName(session.projectDir);
      if (!matches(session.title, folder)) continue;
      entries.add((
        time: DateTime.now(),
        widget: _sessionCard(context, session, null),
      ));
    }
    entries.sort((a, b) => b.time.compareTo(a.time));

    final widgets = <Widget>[];
    String? currentGroup;
    var index = 0;
    for (final entry in entries) {
      final group = _groupOf(entry.time);
      if (group != currentGroup) {
        currentGroup = group;
        widgets.add(_groupHeader(context, group));
      }
      widgets.add(
        FadeIn(
          delay: Duration(milliseconds: 18 * (index % 8)),
          child: entry.widget,
        ),
      );
      index++;
    }
    if (widgets.isEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
          child: Column(
            children: [
              Icon(Icons.forum_outlined, size: 22, color: theme.hintColor),
              const SizedBox(height: 10),
              Text(
                query.isEmpty ? 'No sessions yet' : 'No matches',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                query.isEmpty
                    ? 'New Task opens a session in your last project.'
                    : 'Try a different search.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return widgets;
  }

  static String _groupOf(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (!time.isBefore(today)) return 'Today';
    final days = now.difference(time).inDays;
    if (days < 7) return 'This Week';
    if (days < 30) return 'This Month';
    return 'Older';
  }

  Widget _groupHeader(BuildContext context, String label) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 6),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.hintColor.withValues(alpha: 0.8),
          fontWeight: FontWeight.w600,
          fontSize: 10.5,
          letterSpacing: 0.9,
        ),
      ),
    );
  }

  Widget _sessionCard(
    BuildContext context,
    SessionController session,
    DateTime? time,
  ) {
    return SessionRow(
      title: session.title,
      folder: _folderName(session.projectDir),
      time: time,
      status: session.streaming
          ? CardStatus.running
          : (session.unread ? CardStatus.unread : CardStatus.idle),
      selected: identical(_selected, session),
      onTap: () => _select(session),
      menu: _sessionMenu(context, session),
    );
  }

  Widget _savedCard(BuildContext context, PiSession saved) {
    return SessionRow(
      title: saved.title,
      folder: _folderName(saved.cwd ?? ''),
      time: saved.modified,
      status: CardStatus.saved,
      selected: false,
      onTap: () => _openSession(
        saved.cwd ?? saved.path,
        resumePath: saved.path,
        resumeTitle: saved.title,
      ),
      menu: _savedMenu(context, saved),
    );
  }

  Widget _sessionMenu(BuildContext context, SessionController session) {
    final theme = Theme.of(context);
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.edit_outlined, size: 16),
          onPressed: () => _renameSession(session),
          child: const Text('Rename'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.archive_outlined, size: 16),
          onPressed: () => _archiveSession(session),
          child: const Text('Archive'),
        ),
        MenuItemButton(
          leadingIcon: Icon(
            Icons.delete_outline,
            size: 16,
            color: theme.colorScheme.error,
          ),
          onPressed: () => _deleteSession(session),
          child: Text(
            'Delete',
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      ],
      builder: (context, controller, child) => _menuDots(controller),
    );
  }

  Widget _savedMenu(BuildContext context, PiSession saved) {
    final theme = Theme.of(context);
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.archive_outlined, size: 16),
          onPressed: () => _archivePath(saved.path),
          child: const Text('Archive'),
        ),
        MenuItemButton(
          leadingIcon: Icon(
            Icons.delete_outline,
            size: 16,
            color: theme.colorScheme.error,
          ),
          onPressed: () => _deletePath(saved.path),
          child: Text(
            'Delete',
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
      ],
      builder: (context, controller, child) => _menuDots(controller),
    );
  }

  Widget _menuDots(MenuController controller) {
    return HoverTint(
      radius: 4,
      alpha: 0.09,
      onTap: () => controller.isOpen ? controller.close() : controller.open(),
      child: const Padding(
        padding: EdgeInsets.all(3),
        child: Icon(Icons.more_vert, size: 15),
      ),
    );
  }

  Future<void> _openSession(
    String projectDir, {
    String? resumePath,
    String? worktreeBranch,
    String? resumeTitle,
    bool remember = true,
  }) async {
    if (remember) await _rememberProject(projectDir);
    _lastProjectDir = projectDir;
    if (resumePath != null) {
      // Already open? Just switch to it instead of spawning a second process.
      for (final session in _sessions) {
        if (session.matchesSession(resumePath)) {
          _select(session);
          _toast('Already open — switched to it');
          return;
        }
      }
    }
    final controller = SessionController(
      projectDir: projectDir,
      worktreeBranch: worktreeBranch,
      fallbackTitle: resumeTitle,
      sourcePath: resumePath,
    );
    controller.addListener(_onControllerChanged);
    setState(() {
      _sessions.add(controller);
      _selected = controller;
    });
    // Live immediately, so model/reasoning menus work right away.
    await controller.connect(resumePath: resumePath);
    _scrollToEnd(force: true);
  }

  Future<void> _openProject(String projectDir) async {
    for (final session in _sessions.reversed) {
      if (_sameProject(session.projectDir, projectDir)) {
        _select(session);
        return;
      }
    }
    await _openSession(projectDir);
  }

  Future<void> _openWorktreeSession(String projectDir) async {
    try {
      final worktree = await createWorktree(projectDir);
      await _openSession(
        worktree.path,
        worktreeBranch: worktree.branch,
        remember: false,
      );
      _toast('Worktree: ${worktree.branch}');
    } catch (error) {
      _toast('Worktree failed: $error');
    }
  }

  Future<void> _rememberProject(String dir) async {
    final normalized = SessionController.normalizePath(dir);
    if (_projects.any(
      (p) => SessionController.normalizePath(p) == normalized,
    )) {
      return;
    }
    _projects.add(dir);
    await _projectsStore.save(_projects);
  }

  /// Persisted projects plus any directory that currently has an open session
  /// (e.g. worktrees, which are not persisted). Deduplicated the way Windows
  /// compares paths, so `D:\X` and `d:\x` are one entry.
  List<String> _allProjects() {
    final dirs = <String>[];
    final seen = <String>{};
    for (final dir in [
      ..._projects,
      for (final session in _sessions) session.projectDir,
    ]) {
      if (dir.trim().isEmpty) continue;
      if (seen.add(SessionController.normalizePath(dir))) dirs.add(dir);
    }
    return dirs;
  }

  void _select(SessionController session) {
    setState(() {
      _selected = session;
      _lastProjectDir = session.projectDir;
      session.unread = false;
      _composer.clear();
    });
    _scrollToEnd(force: true);
  }

  void _closeSession(SessionController session) {
    session.removeListener(_onControllerChanged);
    session.dispose();
    setState(() {
      _sessions.remove(session);
      if (identical(_selected, session)) {
        _selected = _sessions.isEmpty ? null : _sessions.last;
      }
    });
    // The closed session should reappear under its project's saved list.
    _loadSavedSessions();
  }

  Future<String?> _pickFolder({String title = 'Choose project folder'}) async {
    if (Platform.isLinux) {
      // Native zenity/kdialog dialog when available; falls back to the text
      // prompt below (pickFolder returns null without those tools).
      try {
        final picked = pickFolder(title: title);
        if (picked != null) return picked;
        return await _promptForFolder();
      } catch (error) {
        _toast('Folder picker failed: $error');
        return null;
      }
    }
    if (Platform.isWindows) {
      try {
        return pickFolder(title: title);
      } catch (error) {
        _toast('Folder picker failed: $error');
        return null;
      }
    }
    return _promptForFolder();
  }

  Future<void> _addProject() async {
    final picked = await _pickFolder(title: 'Add project folder');
    if (picked == null || picked.trim().isEmpty) return;
    final path = picked.trim();
    if (!Directory(path).existsSync()) {
      _toast('Folder not found: $path');
      return;
    }
    await _openSession(path);
  }

  Future<void> _renameSession(SessionController session) async {
    final controller = TextEditingController(text: session.sessionName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename session'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Session name'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await session.rename(name);
      if (mounted) _loadSavedSessions();
    }
  }

  Future<void> _archiveSession(SessionController session) =>
      _archivePath(session.sourcePath ?? session.sessionFile, session: session);

  Future<void> _archivePath(String? path, {SessionController? session}) async {
    if (path != null && !_isArchived(path)) {
      _archived.add(path);
      await _archiveStore.save(_archived);
    }
    if (session != null) {
      _closeSession(session);
    } else {
      await _loadSavedSessions();
    }
    _toast('Archived — hidden from the sidebar');
  }

  bool _isArchived(String path) {
    final normalized = SessionController.normalizePath(path);
    return _archived.any(
      (p) => SessionController.normalizePath(p) == normalized,
    );
  }

  Future<void> _deleteSession(SessionController session) =>
      _deletePath(session.sourcePath ?? session.sessionFile, session: session);

  Future<void> _deletePath(String? path, {SessionController? session}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete session?'),
        content: Text(
          path == null
              ? 'This session has no saved file yet.'
              : 'Permanently deletes the session file:\n\n$path',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (path != null) {
      try {
        final file = File(path);
        if (file.existsSync()) await file.delete();
      } catch (error) {
        _toast('Delete failed: $error');
      }
      final normalized = SessionController.normalizePath(path);
      _archived.removeWhere(
        (p) => SessionController.normalizePath(p) == normalized,
      );
      await _archiveStore.save(_archived);
    }
    if (session != null) {
      _closeSession(session);
    } else {
      await _loadSavedSessions();
    }
    _toast('Deleted');
  }

  /// Reveals older history when the transcript is scrolled near the top.
  /// The list is reversed (newest at offset zero), so prepends grow the far
  /// end and the viewport never moves — loading is just the call, with no
  /// scroll compensation to mistime.
  void _maybeLoadOlder(SessionController session) {
    if (_loadingOlder || !session.hasHiddenHistory) return;
    _loadingOlder = true;
    try {
      session.loadOlderHistory();
    } finally {
      _loadingOlder = false;
    }
  }

  /// Right-hand panel: Review (git diff), Files (tree) and Terminal.
  Widget _rail(BuildContext context, SessionController session) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(left: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
            child: Row(
              children: [
                RailTabButton(
                  icon: Icons.difference_outlined,
                  label: 'Review',
                  active: _railTab == RailTab.review,
                  onTap: () => setState(() => _railTab = RailTab.review),
                ),
                RailTabButton(
                  icon: Icons.folder_outlined,
                  label: 'Files',
                  active: _railTab == RailTab.files,
                  onTap: () => setState(() => _railTab = RailTab.files),
                ),
                RailTabButton(
                  icon: Icons.terminal,
                  label: 'Terminal',
                  active: _railTab == RailTab.terminal,
                  onTap: () => setState(() => _railTab = RailTab.terminal),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => setState(() => _showRail = false),
                  icon: const Icon(Icons.close, size: 15),
                  tooltip: 'Close panel',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: AnimatedSwitcher(
              duration: motion(context, 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.02, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(_railTab),
                child: switch (_railTab) {
                  RailTab.review => DiffView(
                    workingDirectory: session.projectDir,
                    key: ValueKey(session.projectDir),
                  ),
                  RailTab.files => FileTree(root: session.projectDir),
                  RailTab.terminal => TerminalPanel(
                    workingDirectory: session.projectDir,
                  ),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptForFolder() {
    final controller = TextEditingController(
      text:
          Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          '',
    );
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add project folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: r'C:\path\to\project'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  /// Thin draggable splitter between panes; highlights on hover and resets to
  /// the default width on double-click.
  Widget _splitter({
    required ValueChanged<double> onDrag,
    required VoidCallback onReset,
    Color? color,
  }) {
    return SplitHandle(onDrag: onDrag, onReset: onReset, color: color);
  }

  /// Invisible 6px bands that start native window resizing. The Flutter view
  /// covers the entire window, so the OS cannot hit-test the edges itself.
  List<Widget> _resizeHandles() {
    const band = 6.0;
    Widget edge({
      required Alignment alignment,
      required MouseCursor cursor,
      required int code,
      required double width,
      required double height,
    }) {
      return Align(
        alignment: alignment,
        child: MouseRegion(
          cursor: cursor,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) => beginWindowResize(code),
            child: SizedBox(width: width, height: height),
          ),
        ),
      );
    }

    return [
      edge(
        alignment: Alignment.centerLeft,
        cursor: SystemMouseCursors.resizeLeftRight,
        code: htLeft,
        width: band,
        height: double.infinity,
      ),
      edge(
        alignment: Alignment.centerRight,
        cursor: SystemMouseCursors.resizeLeftRight,
        code: htRight,
        width: band,
        height: double.infinity,
      ),
      edge(
        alignment: Alignment.topCenter,
        cursor: SystemMouseCursors.resizeUpDown,
        code: htTop,
        width: double.infinity,
        height: band,
      ),
      edge(
        alignment: Alignment.bottomCenter,
        cursor: SystemMouseCursors.resizeUpDown,
        code: htBottom,
        width: double.infinity,
        height: band,
      ),
      edge(
        alignment: Alignment.topLeft,
        cursor: SystemMouseCursors.resizeUpLeftDownRight,
        code: htTopLeft,
        width: band,
        height: band,
      ),
      edge(
        alignment: Alignment.topRight,
        cursor: SystemMouseCursors.resizeUpRightDownLeft,
        code: htTopRight,
        width: band,
        height: band,
      ),
      edge(
        alignment: Alignment.bottomLeft,
        cursor: SystemMouseCursors.resizeUpRightDownLeft,
        code: htBottomLeft,
        width: band,
        height: band,
      ),
      edge(
        alignment: Alignment.bottomRight,
        cursor: SystemMouseCursors.resizeUpLeftDownRight,
        code: htBottomRight,
        width: band,
        height: band,
      ),
    ];
  }

  String get _userName =>
      Platform.environment['USERNAME'] ??
      Platform.environment['USER'] ??
      'Khaled';

  /// Provider/model pairs the open session reported, for the settings model
  /// picker. Empty when nothing is connected, which makes the page fall back to
  /// a free-text field.
  List<({String provider, String id, String label})> _availableModels() {
    final session = _selected;
    if (session == null) return const [];
    final seen = <String>{};
    final out = <({String provider, String id, String label})>[];
    for (final model in session.models) {
      final id = '${model['id'] ?? ''}';
      if (id.isEmpty || !seen.add(id)) continue;
      out.add((
        provider: '${model['provider'] ?? ''}',
        id: id,
        label: '${model['name'] ?? id}',
      ));
    }
    out.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return out;
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// New Task: straight into a session in the last used project; the home
  /// folder when no project exists yet.
  Future<void> _newTask() async {
    final projects = _allProjects();
    final project =
        _lastProjectDir ?? (projects.isNotEmpty ? projects.last : null);
    if (project != null && Directory(project).existsSync()) {
      await _openSession(project);
      return;
    }
    final home =
        Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    await _openSession(home, remember: false);
  }

  void _openInExplorer(String path) {
    if (!Directory(path).existsSync()) {
      _toast('Folder not found: $path');
      return;
    }
    Process.start(Platform.isWindows ? 'explorer' : 'xdg-open', [path]);
  }

  // --------------------------------------------------------- footer menus

  /// Project chip: pick the project to work in (opens a session there),
  /// or add a new project folder.
  Widget _projectChip(BuildContext context, SessionController session) {
    final theme = Theme.of(context);
    final projects = _allProjects();
    final current = session.projectDir;
    // Locked once the conversation has started: pi's cwd can't change.
    if (session.hasStarted) {
      return FooterChip(
        icon: Icons.folder_outlined,
        label: _folderName(current),
        tooltip: 'Project is fixed once the session has messages',
      );
    }
    return MenuAnchor(
      menuChildren: [
        for (final project in projects)
          MenuItemButton(
            onPressed: () {
              if (_sameProject(project, current)) return;
              // Pending session: just retarget it, don't spawn another.
              session.setProject(project);
              _rememberProject(project);
            },
            leadingIcon: Icon(
              _sameProject(project, current)
                  ? Icons.check
                  : Icons.folder_outlined,
              size: 16,
              color: _sameProject(project, current)
                  ? theme.colorScheme.primary
                  : null,
            ),
            child: Tooltip(message: project, child: Text(_folderName(project))),
          ),
        const Divider(height: 8),
        MenuItemButton(
          leadingIcon: const Icon(Icons.create_new_folder_outlined, size: 16),
          onPressed: () async {
            final picked = await _pickFolder(title: 'New project folder');
            if (picked == null || picked.trim().isEmpty) return;
            final path = picked.trim();
            if (!Directory(path).existsSync()) {
              _toast('Folder not found: $path');
              return;
            }
            session.setProject(path);
            _rememberProject(path);
          },
          child: const Text('New project…'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.folder_open, size: 16),
          onPressed: () => _openInExplorer(current),
          child: const Text('Open folder in Explorer'),
        ),
      ],
      builder: (context, controller, child) => FooterChip(
        icon: Icons.folder_outlined,
        label: _folderName(current),
        tooltip: current,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  /// Local chip: "Work in" — local machine or a fresh git worktree.
  Widget _localChip(BuildContext context, SessionController session) {
    return MenuAnchor(
      menuChildren: [
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: Text('Work in'),
        ),
        MenuItemButton(
          leadingIcon: Icon(Icons.check, size: 16),
          onPressed: () {},
          child: const Text('Local'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.call_split, size: 16),
          onPressed: () => _openWorktreeSession(session.projectDir),
          child: const Text('New worktree'),
        ),
      ],
      builder: (context, controller, child) => FooterChip(
        icon: Icons.desktop_windows_outlined,
        label: 'Local',
        tooltip: 'Runs on this machine',
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  /// Branch chip: searchable branch switcher with a create option.
  Widget _branchChip(BuildContext context, SessionController session) {
    final theme = Theme.of(context);
    return MenuAnchor(
      onOpen: () {
        _branchSearchController.clear();
        session.loadGitInfo();
      },
      menuChildren: [
        SizedBox(
          width: 300,
          child: StatefulBuilder(
            builder: (context, setMenuState) {
              final query = _branchSearchController.text.trim().toLowerCase();
              final branches = session.gitBranches
                  .where(
                    (branch) =>
                        query.isEmpty || branch.toLowerCase().contains(query),
                  )
                  .toList();
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                    child: TextField(
                      controller: _branchSearchController,
                      onChanged: (_) => setMenuState(() {}),
                      decoration: InputDecoration(
                        hintText:
                            'Search ${_folderName(session.projectDir)} branches',
                        prefixIcon: const Icon(Icons.search, size: 15),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 30,
                          minHeight: 30,
                        ),
                      ),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final branch in branches)
                            MenuItemButton(
                              leadingIcon: Icon(
                                branch == session.branchLabel
                                    ? Icons.check
                                    : Icons.call_split,
                                size: 16,
                                color: branch == session.branchLabel
                                    ? theme.colorScheme.primary
                                    : null,
                              ),
                              onPressed: () => _checkoutBranch(session, branch),
                              child: Text(branch),
                            ),
                          if (branches.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text('No branches match'),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 8),
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.add, size: 16),
                    onPressed: () => _createBranch(session),
                    child: const Text('Create and checkout new branch…'),
                  ),
                ],
              );
            },
          ),
        ),
      ],
      builder: (context, controller, child) => FooterChip(
        icon: Icons.call_split,
        label: session.branchLabel ?? 'no branch',
        tooltip: 'Switch branch',
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  Future<void> _checkoutBranch(SessionController session, String branch) async {
    final result = await checkoutBranch(session.projectDir, branch);
    if (!result.ok) {
      _toast('Checkout failed: ${result.error}');
      return;
    }
    await session.loadGitInfo();
    _toast('Switched to $branch');
  }

  Future<void> _createBranch(SessionController session) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New branch'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'branch-name'),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    final result = await createBranch(session.projectDir, name.trim());
    if (!result.ok) {
      _toast('Branch creation failed: ${result.error}');
      return;
    }
    await session.loadGitInfo();
    _toast('Created and switched to ${name.trim()}');
  }

  static bool _sameProject(String a, String b) =>
      SessionController.normalizePath(a) == SessionController.normalizePath(b);

  Future<void> _send() async {
    final session = _selected;
    final text = _composer.text.trim();
    if (session == null || text.isEmpty) return;
    _composer.clear();
    await session.send(text);
  }

  /// Inserts an `@path` file mention the way pi expects them in prompts.
  void _attachFile() {
    final path = pickFile(title: 'Add file to prompt');
    if (path == null) return;
    final text = _composer.text;
    final separator = text.isEmpty || text.endsWith(' ') ? '' : ' ';
    _composer.text = '$text$separator@$path ';
    _composer.selection = TextSelection.collapsed(
      offset: _composer.text.length,
    );
  }

  /// Null unless exactly one scroll view holds [_scroll]. During
  /// session-switch transitions the outgoing and incoming transcripts briefly
  /// share it, and [ScrollController.position] asserts in that window — every
  /// touch point goes through here so a switch can never crash scrolling.
  ScrollPosition? _transcriptPosition() {
    if (_scroll.positions.length != 1) return null;
    return _scroll.positions.first;
  }

  void _scrollToEnd({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final position = _transcriptPosition();
      if (position == null) return;
      // Reversed list: offset zero is the newest (bottom) end.
      final distance = position.pixels - position.minScrollExtent;
      if (!force && distance >= 120) return;
      if (force || MediaQuery.of(context).disableAnimations) {
        position.jumpTo(position.minScrollExtent);
        return;
      }
      position.animateTo(
        position.minScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  /// Consecutive thinking + tool calls collapse into one activity block, like
  /// the "Processing 2m 20s · 76 token/s" feed in a good agent UI.
  static List<Object> _displayRows(List<ChatItem> items) {
    final rows = <Object>[];
    for (final item in items) {
      if (item.kind != ItemKind.tool && item.kind != ItemKind.thinking) {
        rows.add(item);
        continue;
      }
      if (rows.isNotEmpty && rows.last is List<ChatItem>) {
        (rows.last as List<ChatItem>).add(item);
      } else {
        rows.add(<ChatItem>[item]);
      }
    }
    return rows;
  }

  static String _folderName(String path) {
    final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty);
    return parts.isEmpty ? path : parts.last;
  }

  // --------------------------------------------------------------------- ui

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = _selected;
    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              // Custom chrome is Windows-only: the frameless runner has no
              // native frame. Linux keeps its GTK header bar instead.
              if (Platform.isWindows) const TitleBar(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const minChatWidth = 480.0;
                    // Keep both splitters and the chat's usable width outside
                    // the rail's budget; the 820px ceiling only applies on
                    // wide windows.
                    final maxRailWidth =
                        (constraints.maxWidth -
                                _sidebarWidth -
                                16 -
                                minChatWidth)
                            .clamp(0.0, 820.0)
                            .toDouble();
                    final minRailWidth = maxRailWidth < 320
                        ? maxRailWidth
                        : 320.0;
                    final railWidth = _railWidth
                        .clamp(minRailWidth, maxRailWidth)
                        .toDouble();
                    return Row(
                      children: [
                        SizedBox(
                          width: _sidebarWidth,
                          child: _sidebar(context),
                        ),
                        _splitter(
                          color: _sidebarBackground(context),
                          onDrag: (dx) => setState(
                            () => _sidebarWidth = (_sidebarWidth + dx).clamp(
                              240.0,
                              480.0,
                            ),
                          ),
                          onReset: () => setState(() => _sidebarWidth = 264),
                        ),
                        Expanded(
                          // Opaque shell: the scaffold is transparent on Windows
                          // and only the sidebar may let the wallpaper through —
                          // this covers both the hero and the transcript.
                          child: Container(
                            color: theme.colorScheme.surface,
                            child: AnimatedSwitcher(
                              duration: motion(context, 200),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeIn,
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0, 0.012),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                              child: KeyedSubtree(
                                key: ValueKey(_selected),
                                child: _chatPane(context),
                              ),
                            ),
                          ),
                        ),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: maxRailWidth + 8,
                          ),
                          child: AnimatedSize(
                            duration: motion(context, 220),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.centerRight,
                            child: _showRail && session != null
                                ? Container(
                                    color: theme
                                        .colorScheme
                                        .surfaceContainerLowest,
                                    child: Row(
                                      children: [
                                        _splitter(
                                          color: theme
                                              .colorScheme
                                              .surfaceContainerLowest,
                                          onDrag: (dx) => setState(
                                            () => _railWidth = (railWidth - dx)
                                                .clamp(
                                                  minRailWidth,
                                                  maxRailWidth,
                                                )
                                                .toDouble(),
                                          ),
                                          onReset: () => setState(
                                            () => _railWidth = 520
                                                .clamp(
                                                  minRailWidth,
                                                  maxRailWidth,
                                                )
                                                .toDouble(),
                                          ),
                                        ),
                                        SizedBox(
                                          width: railWidth,
                                          child: _rail(context, session),
                                        ),
                                      ],
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          // Settings is a full page rather than a dialog: it is long, it
          // scrolls, and the edits need room to be reviewed before they reach
          // pi's settings.json. It sits below the title bar so the window
          // controls, and the resize handles added after it, stay live.
          if (_showSettings)
            Positioned(
              top: 34,
              left: 0,
              right: 0,
              bottom: 0,
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): () =>
                      setState(() => _showSettings = false),
                },
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: motion(context, 220),
                  curve: Curves.easeOutCubic,
                  builder: (context, t, child) => Opacity(
                    opacity: t,
                    child: Transform.translate(
                      offset: Offset(0, 10 * (1 - t)),
                      child: child,
                    ),
                  ),
                  child: ColoredBox(
                    color: theme.colorScheme.surface,
                    child: SettingsPage(
                      settings: _piSettings,
                      models: _piModels,
                      availableModels: _availableModels(),
                      projectDir: _selected?.projectDir,
                      onClose: () => setState(() => _showSettings = false),
                    ),
                  ),
                ),
              ),
            ),
          // Native resize bands are Windows-only; the Linux runner has a
          // resizable GTK frame already.
          if (Platform.isWindows) ..._resizeHandles(),
        ],
      ),
    );
  }

  /// The one translucent pane: wallpaper shows through here while the chat
  /// side stays fully opaque. Linux keeps the solid fill. Kept at high
  /// alpha — without a native blur pass (no maintained plugin offers one)
  /// this reads as frosted rather than glass.
  Color _sidebarBackground(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerLowest;
    return Platform.isWindows ? base.withValues(alpha: 0.92) : base;
  }

  Widget _sidebar(BuildContext context) {
    final theme = Theme.of(context);
    final background = _sidebarBackground(context);
    return Container(
      decoration: BoxDecoration(
        color: background,
        border: Border(right: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 6, 0),
            child: Row(
              children: [
                Image.asset('assets/icon/app_icon.png', width: 16, height: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Pi Studio', style: theme.textTheme.titleSmall),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) {
                      _searchQuery = '';
                      _searchController.clear();
                    }
                  }),
                  icon: const Icon(Icons.search, size: 16),
                  tooltip: 'Search sessions',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _sidebarAction(
              context,
              icon: Icons.add_circle_outline,
              label: 'New task',
              onTap: _newTask,
            ),
          ),
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Search sessions'),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
          _sectionHeader(context, 'Recent', onRefresh: _loadSavedSessions),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              children: [
                ..._sessionList(context),
                _sectionHeader(context, 'Projects', onAdd: _addProject),
                for (final project in _allProjects())
                  Tooltip(
                    message: project,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: HoverTint(
                        radius: 8,
                        onTap: () => _openProject(project),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.folder_outlined,
                                size: 15,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _folderName(project),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                              IconButton(
                                onPressed: () => _openSession(project),
                                icon: const Icon(Icons.add, size: 15),
                                tooltip: 'New task in ${_folderName(project)}',
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 26,
                                  minHeight: 26,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  child: Text(
                    _userName.isNotEmpty ? _userName[0].toUpperCase() : 'U',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  tooltip: 'Settings',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  onPressed: () => setState(() => _showSettings = true),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Small-caps section label with an optional trailing action, matching the
  /// time-group headers used further down the list.
  Widget _sectionHeader(
    BuildContext context,
    String label, {
    VoidCallback? onAdd,
    VoidCallback? onRefresh,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 6, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.hintColor.withValues(alpha: 0.8),
                fontWeight: FontWeight.w600,
                fontSize: 10.5,
                letterSpacing: 0.9,
              ),
            ),
          ),
          if (onAdd != null)
            IconButton(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 15),
              tooltip: 'Add project',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            ),
          if (onRefresh != null)
            IconButton(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 14),
              tooltip: 'Reload sessions',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            ),
        ],
      ),
    );
  }

  Widget _sidebarAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool trailingChevron = false,
  }) {
    final theme = Theme.of(context);
    return HoverTint(
      onTap: onTap,
      radius: 6,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          children: [
            Icon(icon, size: 15, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (trailingChevron)
              Icon(Icons.keyboard_arrow_down, size: 15, color: theme.hintColor),
          ],
        ),
      ),
    );
  }

  Widget _chatPane(BuildContext context) {
    final theme = Theme.of(context);
    final session = _selected;
    if (session == null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/icon/app_icon.png', width: 52, height: 52),
              const SizedBox(height: 20),
              Text(
                'What do you want to build?',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pick a project from the sidebar, or start fresh.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    onPressed: _newTask,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('New task'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => _addProject(),
                    child: const Text('Add project'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }
    final rows = _displayRows(session.items);
    // Newest first to match the reversed list below.
    final latestFirst = rows.reversed.toList();
    final chat = Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.circle,
                size: 8,
                color: session.connected ? liveGreen : theme.hintColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      session.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      _folderName(session.projectDir),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              if (session.streaming)
                Text('working…', style: theme.textTheme.bodySmall),
              if (session.hasDiffStats)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Tooltip(
                    message: 'Uncommitted changes — click for the diff',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        setState(() {
                          _showRail = true;
                          _railTab = RailTab.review;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '+${formatCount(session.diffAdditions)}',
                                style: const TextStyle(color: diffAdded),
                              ),
                              const TextSpan(text: '  '),
                              TextSpan(
                                text: '-${formatCount(session.diffDeletions)}',
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ],
                          ),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontFamily: 'GeistMono',
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              IconButton(
                onPressed: session.newSession,
                icon: const Icon(Icons.add_box_outlined, size: 18),
                tooltip: 'New session in this project',
              ),
              IconButton(
                onPressed: () => setState(() => _showRail = !_showRail),
                icon: Icon(
                  _showRail ? Icons.view_sidebar : Icons.view_sidebar_outlined,
                  size: 18,
                ),
                tooltip: 'Toggle panel',
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: session.loading
                  ? const TranscriptSkeleton()
                  : session.items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/icon/app_icon.png',
                            width: 26,
                            height: 26,
                          ),
                          const SizedBox(height: 16),
                          Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(
                                  text: 'What should we build in ',
                                ),
                                TextSpan(
                                  text: _folderName(session.projectDir),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const TextSpan(text: '?'),
                              ],
                            ),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontSize: 21,
                              fontWeight: FontWeight.w400,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (notification) {
                              // Reversed list: the visual top is the max edge.
                              if (notification.metrics.maxScrollExtent -
                                      notification.metrics.pixels <=
                                  400) {
                                _maybeLoadOlder(session);
                              }
                              return false;
                            },
                            // One SelectionArea for the whole transcript: drag-select
                            // spans messages and Ctrl+C copies the lot. Plain
                            // Text/MarkdownBody inside is enough — nested
                            // selectables would each grab the gesture.
                            child: SelectionArea(
                              child: ListView.builder(
                                controller: _scroll,
                                // Newest first: offset zero is the bottom end,
                                // so history prepends grow the far edge and the
                                // viewport holds still with no compensation.
                                reverse: true,
                                // Was 50000px, which kept almost every row of
                                // a long session built and laid out on every
                                // scroll frame. A screen of slack above and
                                // below is enough for smooth scroll-back, and
                                // turn jumps correct themselves (see below).
                                scrollCacheExtent:
                                    const ScrollCacheExtent.pixels(1200.0),
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  16,
                                  16,
                                  24,
                                ),
                                itemCount: latestFirst.length,
                                itemBuilder: (context, index) {
                                  final row = latestFirst[index];
                                  if (row is List<ChatItem>) {
                                    return ActivityBlockView(
                                      items: row,
                                      key: ValueKey(
                                        'blk:${row.first.stableId ?? 'live-$index'}',
                                      ),
                                      live: session.streaming && index == 0,
                                      seconds: session.processingSeconds,
                                      tokensPerSecond: session.tokensPerSecond,
                                    );
                                  }
                                  final item = row as ChatItem;
                                  final stableId = item.stableId;
                                  return ChatItemView(
                                    item,
                                    key: stableId == null
                                        ? null
                                        : ValueKey(stableId),
                                    live:
                                        session.streaming &&
                                        item.kind == ItemKind.assistant &&
                                        index == 0,
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: AnimatedContainer(
                    duration: motion(context, 150),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _composerFocused
                            ? theme.colorScheme.primary.withValues(alpha: 0.55)
                            : theme.dividerColor.withValues(alpha: 0.5),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Focus(
                          onFocusChange: (hasFocus) =>
                              setState(() => _composerFocused = hasFocus),
                          onKeyEvent: (node, event) {
                            // Enter sends; Shift+Enter keeps the newline.
                            if (event is KeyDownEvent &&
                                event.logicalKey == LogicalKeyboardKey.enter &&
                                !HardwareKeyboard.instance.isShiftPressed) {
                              _send();
                              return KeyEventResult.handled;
                            }
                            return KeyEventResult.ignored;
                          },
                          child: TextField(
                            controller: _composer,
                            minLines: 2,
                            maxLines: 8,
                            style: theme.textTheme.bodyMedium,
                            decoration: const InputDecoration(
                              hintText: 'Ask anything, @ to add files, or / for commands',
                              border: InputBorder.none,
                              filled: false,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              onPressed: session.connected ? _attachFile : null,
                              icon: const Icon(Icons.add, size: 20),
                              tooltip: 'Insert @file mention',
                              visualDensity: VisualDensity.compact,
                            ),
                            const SizedBox(width: 4),
                            // Flexible: absorbs sub-pixel rounding so the row
                            // never stripes at narrow widths.
                            AccessPill(session: session),
                            const Spacer(),
                            if (session.streaming) ...[
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 12),
                            ],
                            if (session.isStarted)
                              ContextRing(session: session),
                            AgentSettingsMenu(session: session),
                            const SizedBox(width: 8),
                            SendButton(
                              enabled: true,
                              streaming: session.streaming,
                              onTap: session.streaming ? session.abort : _send,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Divider(
                  height: 12,
                  indent: 10,
                  endIndent: 10,
                  color: theme.dividerColor.withValues(alpha: 0.7),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Row(
                    children: [
                      _projectChip(context, session),
                      const SizedBox(width: 2),
                      _localChip(context, session),
                      if (session.branchLabel != null) ...[
                        const SizedBox(width: 2),
                        _branchChip(context, session),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    // Opaque: the scaffold behind is transparent on Windows, and only the
    // sidebar is meant to let the wallpaper through.
    return chat;
  }
}
