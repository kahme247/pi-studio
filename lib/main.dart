import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'git/git_ops.dart';
import 'pi/session_store.dart';
import 'platform/folder_picker.dart';
import 'platform/window_controls.dart';
import 'settings/pi_settings.dart';
import 'settings/settings_page.dart';
import 'state/projects_store.dart';
import 'state/session_controller.dart';
import 'ui/smooth_scroll.dart';

void main() => runApp(const PiStudioApp());

/// omp.sh inspired theme: pure pitch black background (#000000),
/// elevated ink surfaces (#0A0A0C), crisp off-white typography (#F7F7F8),
/// omp magenta (#FF3B88) as primary accent, and cyan (#38BDF8) as secondary.
ThemeData _appTheme() {
  const ink0 = Color(0xFF000000);
  const ink1 = Color(0xFF0A0A0C);
  const ink5 = Color(0xFF73737A);
  const ink7 = Color(0xFFCBCCD2);
  const ink9 = Color(0xFFF7F7F8);
  const magenta = Color(0xFFD4688E);
  const cyan = Color(0xFF62ADC9);
  const rule = Color(0x14FFFFFF);

  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: magenta,
    onPrimary: ink0,
    primaryContainer: Color(0x20D4688E),
    onPrimaryContainer: ink9,
    secondary: cyan,
    onSecondary: ink0,
    secondaryContainer: Color(0x2062ADC9),
    onSecondaryContainer: ink9,
    surface: ink0,
    onSurface: ink9,
    onSurfaceVariant: ink7,
    surfaceContainerLowest: ink0,
    surfaceContainerLow: Color(0xFF060608),
    surfaceContainer: ink1,
    surfaceContainerHigh: Color(0xFF101014),
    surfaceContainerHighest: Color(0xFF16161C),
    outline: ink5,
    outlineVariant: rule,
    error: Color(0xFFCF5668),
    onError: ink9,
  );

  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'Geist',
  );

  return base.copyWith(
    hintColor: ink5,
    scaffoldBackgroundColor: ink0,
    visualDensity: VisualDensity.compact,
    // InkSparkle builds a per-tap GPU shader. That is a touch idiom: it costs
    // frames here and reads as noise under a mouse. A cheap ripple plus the
    // hover states below carry pointer feedback instead.
    splashFactory: InkRipple.splashFactory,
    // Bare InkWell (the majority of this UI) falls back to these, so one line
    // here gives every hand-rolled control a hover/focus response.
    hoverColor: ink9.withValues(alpha: 0.055),
    highlightColor: ink9.withValues(alpha: 0.04),
    focusColor: magenta.withValues(alpha: 0.16),
    dividerTheme: const DividerThemeData(color: rule, thickness: 1, space: 1),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(5),
      radius: const Radius.circular(3),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => ink5.withValues(
          alpha: states.contains(WidgetState.hovered) ? 0.6 : 0.28,
        ),
      ),
    ),
    textTheme: base.textTheme.copyWith(
      titleLarge: base.textTheme.titleLarge
          ?.copyWith(fontSize: 17.5, fontWeight: FontWeight.w600, color: ink9),
      titleSmall: base.textTheme.titleSmall
          ?.copyWith(fontSize: 14.5, fontWeight: FontWeight.w600, color: ink9),
      bodyMedium: base.textTheme.bodyMedium
          ?.copyWith(fontSize: 14.5, height: 1.55, color: ink9),
      bodySmall: base.textTheme.bodySmall
          ?.copyWith(fontSize: 13, height: 1.35, color: ink7),
      labelLarge: base.textTheme.labelLarge
          ?.copyWith(fontSize: 13.5, fontWeight: FontWeight.w500, color: ink9),
      labelSmall: base.textTheme.labelSmall
          ?.copyWith(fontSize: 12, color: ink5),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: ink1,
      hintStyle: const TextStyle(
        color: ink5,
        fontWeight: FontWeight.w400,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      isDense: true,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: ink1,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: rule),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(ink1),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: 6),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: rule),
          ),
        ),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 3500),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: ink1,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: rule),
      ),
      textStyle: const TextStyle(fontSize: 12.5, color: ink9),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        overlayColor: ink0.withValues(alpha: 0.14),
        animationDuration: const Duration(milliseconds: 110),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 30),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
        overlayColor: ink9.withValues(alpha: 0.08),
        animationDuration: const Duration(milliseconds: 110),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(30, 30),
        iconSize: 18,
        padding: EdgeInsets.zero,
        // Without an overlay an IconButton looks inert until you press it.
        hoverColor: ink9.withValues(alpha: 0.09),
        highlightColor: ink9.withValues(alpha: 0.11),
        animationDuration: const Duration(milliseconds: 110),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      dense: true,
      visualDensity: VisualDensity.compact,
      minVerticalPadding: 2,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: ink1,
      contentTextStyle:
          const TextStyle(fontSize: 13.5, color: ink9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: rule),
      ),
    ),
  );
}

class PiStudioApp extends StatelessWidget {
  const PiStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pi Studio',
      debugShowCheckedModeBanner: false,
      theme: _appTheme(),
      home: const HomePage(),
    );
  }
}

/// Animation duration that collapses to zero when the OS asks for reduced
/// motion.
Duration _motion(BuildContext context, [int ms = 140]) =>
    MediaQuery.of(context).disableAnimations
        ? Duration.zero
        : Duration(milliseconds: ms);

/// Pointer feedback for the small hand-rolled controls in this UI: declares the
/// click cursor and eases a tint in on hover. A bare [InkWell] gives no
/// continuous response under a mouse, which is what reads as "inert".
///
/// This paints its own background rather than relying on ink splashes, because
/// the sidebar and rail sit on opaque containers — an ink splash would be
/// painted on the Material *behind* them and never seen.
class _HoverTint extends StatefulWidget {
  const _HoverTint({
    required this.child,
    this.onTap,
    this.radius = 8,
    this.alpha = 0.06,
    this.baseColor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final double alpha;

  /// Static fill under the hover tint, e.g. a selected row's highlight.
  final Color? baseColor;

  @override
  State<_HoverTint> createState() => _HoverTintState();
}

class _HoverTintState extends State<_HoverTint> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = theme.colorScheme.onSurface;
    final interactive = widget.onTap != null;
    final base = widget.baseColor ?? Colors.transparent;
    // Compose rather than replace, so a selected row still responds to hover.
    final color = _hovered && interactive
        ? Color.alphaBlend(tint.withValues(alpha: widget.alpha), base)
        : base;
    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: interactive
            ? HitTestBehavior.opaque
            : HitTestBehavior.deferToChild,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: _motion(context, 110),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Block caret pinned to the tail of an assistant message that is still
/// streaming, so the transcript reads as live rather than settled.
class _StreamCaret extends StatefulWidget {
  const _StreamCaret({required this.color});

  final Color color;

  @override
  State<_StreamCaret> createState() => _StreamCaretState();
}

class _StreamCaretState extends State<_StreamCaret>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat(reverse: true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hold it mid-blink rather than animate when the OS asks for less motion.
    if (MediaQuery.of(context).disableAnimations) {
      _controller.stop();
      _controller.value = 0.6;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.2, end: 1).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: 4,
        height: 9,
        margin: const EdgeInsets.only(left: 3, top: 3),
        decoration: BoxDecoration(
          color: widget.color,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }
}

/// Rail tab: the active tab holds a primary tint, inactive tabs ease toward it
/// on hover so the tab strip responds under the pointer.
class _RailTabButton extends StatefulWidget {
  const _RailTabButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_RailTabButton> createState() => _RailTabButtonState();
}

class _RailTabButtonState extends State<_RailTabButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = widget.active;
    final background = active
        ? theme.colorScheme.primary.withValues(alpha: 0.14)
        : (_hovered
            ? theme.colorScheme.onSurface.withValues(alpha: 0.07)
            : Colors.transparent);
    final iconColor = active
        ? theme.colorScheme.primary
        : (_hovered ? theme.colorScheme.onSurface : theme.hintColor);
    final labelColor = active
        ? theme.colorScheme.primary
        : (_hovered
            ? theme.colorScheme.onSurface
            : theme.colorScheme.onSurfaceVariant);
    final duration = _motion(context, 120);

    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: iconColor),
                  duration: duration,
                  curve: Curves.easeOut,
                  builder: (context, color, _) =>
                      Icon(widget.icon, size: 14, color: color),
                ),
                const SizedBox(width: 6),
                TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: labelColor),
                  duration: duration,
                  curve: Curves.easeOut,
                  builder: (context, color, _) => Text(
                    widget.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight:
                          active ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sidebar card indicator state.
enum _CardStatus { idle, running, unread, saved }

/// Tabs of the right-hand panel.
enum _RailTab { review, files, terminal }

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
  _RailTab _railTab = _RailTab.review;
  var _showSettings = false;
  final _piSettings = PiSettings();
  var _loadingOlder = false;
  var _sidebarWidth = 320.0;
  var _railWidth = 520.0;
  final Map<int, GlobalKey> _turnKeys = {};
  int _activeTurn = 0;
  var _isProgrammaticScroll = false;
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

    final archivedPaths =
        _archived.map(SessionController.normalizePath).toSet();
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
        _FadeIn(
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
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor),
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
    return _SessionRow(
      title: session.title,
      folder: _folderName(session.projectDir),
      time: time,
      status: session.streaming
          ? _CardStatus.running
          : (session.unread ? _CardStatus.unread : _CardStatus.idle),
      selected: identical(_selected, session),
      onTap: () => _select(session),
      menu: _sessionMenu(context, session),
    );
  }

  Widget _savedCard(BuildContext context, PiSession saved) {
    return _SessionRow(
      title: saved.title,
      folder: _folderName(saved.cwd ?? ''),
      time: saved.modified,
      status: _CardStatus.saved,
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
    return _HoverTint(
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
    if (_projects
        .any((p) => SessionController.normalizePath(p) == normalized)) {
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
    return _archived
        .any((p) => SessionController.normalizePath(p) == normalized);
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

  /// Reveals older history when the transcript is scrolled to the top,
  /// keeping the visible position stable.
  Future<void> _maybeLoadOlder(SessionController session) async {
    if (_loadingOlder || !session.hasHiddenHistory) return;
    _loadingOlder = true;
    final hadClients = _scroll.hasClients;
    final before = hadClients ? _scroll.position.maxScrollExtent : 0.0;
    final offset = hadClients ? _scroll.position.pixels : 0.0;
    session.loadOlderHistory();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (mounted && _scroll.hasClients) {
      final after = _scroll.position.maxScrollExtent;
      _scroll.jumpTo((offset + (after - before)).clamp(0.0, after));
    }
    _loadingOlder = false;
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
                _RailTabButton(
                  icon: Icons.difference_outlined,
                  label: 'Review',
                  active: _railTab == _RailTab.review,
                  onTap: () => setState(() => _railTab = _RailTab.review),
                ),
                _RailTabButton(
                  icon: Icons.folder_outlined,
                  label: 'Files',
                  active: _railTab == _RailTab.files,
                  onTap: () => setState(() => _railTab = _RailTab.files),
                ),
                _RailTabButton(
                  icon: Icons.terminal,
                  label: 'Terminal',
                  active: _railTab == _RailTab.terminal,
                  onTap: () => setState(() => _railTab = _RailTab.terminal),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => setState(() => _showRail = false),
                  icon: const Icon(Icons.close, size: 15),
                  tooltip: 'Close panel',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: AnimatedSwitcher(
              duration: _motion(context, 180),
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
                  _RailTab.review => _DiffView(
                      workingDirectory: session.projectDir,
                      key: ValueKey(session.projectDir),
                    ),
                  _RailTab.files => _FileTree(root: session.projectDir),
                  _RailTab.terminal =>
                    _TerminalPanel(workingDirectory: session.projectDir),
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
      text: Platform.environment['USERPROFILE'] ??
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
  }) {
    return _SplitHandle(onDrag: onDrag, onReset: onReset);
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
    final project = _lastProjectDir ??
        (projects.isNotEmpty ? projects.last : null);
    if (project != null && Directory(project).existsSync()) {
      await _openSession(project);
      return;
    }
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    await _openSession(home, remember: false);
  }

  void _openInExplorer(String path) {
    if (!Directory(path).existsSync()) {
      _toast('Folder not found: $path');
      return;
    }
    Process.start('explorer', [path]);
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
      return _FooterChip(
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
            child: Tooltip(
              message: project,
              child: Text(_folderName(project)),
            ),
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
      builder: (context, controller, child) => _FooterChip(
        icon: Icons.folder_outlined,
        label: _folderName(current),
        tooltip: current,
        onTap: () =>
            controller.isOpen ? controller.close() : controller.open(),
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
      builder: (context, controller, child) => _FooterChip(
        icon: Icons.desktop_windows_outlined,
        label: 'Local',
        tooltip: 'Runs on this machine',
        onTap: () =>
            controller.isOpen ? controller.close() : controller.open(),
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
                  .where((branch) =>
                      query.isEmpty || branch.toLowerCase().contains(query))
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
      builder: (context, controller, child) => _FooterChip(
        icon: Icons.call_split,
        label: session.branchLabel ?? 'no branch',
        tooltip: 'Switch branch',
        onTap: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  Future<void> _checkoutBranch(
    SessionController session,
    String branch,
  ) async {
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
    _composer.selection =
        TextSelection.collapsed(offset: _composer.text.length);
  }

  void _scrollToEnd({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      final distance = position.maxScrollExtent - position.pixels;
      if (!force && distance >= 120) return;
      if (force || MediaQuery.of(context).disableAnimations) {
        _scroll.jumpTo(position.maxScrollExtent);
        return;
      }
      _scroll.animateTo(
        position.maxScrollExtent,
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
              const _TitleBar(),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(width: _sidebarWidth, child: _sidebar(context)),
                    _splitter(
                      onDrag: (dx) => setState(
                        () => _sidebarWidth =
                            (_sidebarWidth + dx).clamp(240.0, 480.0),
                      ),
                      onReset: () => setState(() => _sidebarWidth = 320),
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: _motion(context, 200),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) => FadeTransition(
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
                    AnimatedSize(
                      duration: _motion(context, 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.centerRight,
                      child: _showRail && session != null
                          ? Row(
                              children: [
                                _splitter(
                                  onDrag: (dx) => setState(
                                    () => _railWidth =
                                        (_railWidth - dx).clamp(320.0, 820.0),
                                  ),
                                  onReset: () =>
                                      setState(() => _railWidth = 520),
                                ),
                                SizedBox(
                                  width: _railWidth,
                                  child: _rail(context, session),
                                ),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
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
                  duration: _motion(context, 220),
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
                      availableModels: _availableModels(),
                      onClose: () => setState(() => _showSettings = false),
                    ),
                  ),
                ),
              ),
            ),
          ..._resizeHandles(),
        ],
      ),
    );
  }

  Widget _sidebar(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(right: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          _sidebarAction(
            context,
            icon: Icons.add_box_outlined,
            label: 'New Task',
            onTap: _newTask,
          ),
          Row(
            children: [
              Expanded(
                child: _sidebarAction(
                  context,
                  icon: Icons.search,
                  label: 'Search',
                  onTap: () => setState(() {
                    _searching = !_searching;
                    if (!_searching) {
                      _searchQuery = '';
                      _searchController.clear();
                    }
                  }),
                ),
              ),
              IconButton(
                onPressed: _loadSavedSessions,
                icon: const Icon(Icons.refresh, size: 15),
                tooltip: 'Reload sessions',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              const SizedBox(width: 10),
            ],
          ),
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Search sessions'),
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
              children: _sessionList(context),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor:
                      theme.colorScheme.surfaceContainerHighest,
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
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => setState(() => _showSettings = true),
                ),
              ],
            ),
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
    return _HoverTint(
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
              Icon(Icons.keyboard_arrow_down,
                  size: 15, color: theme.hintColor),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal, size: 40, color: theme.hintColor),
            const SizedBox(height: 12),
            Text(
              'No session selected.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _addProject,
              icon: const Icon(Icons.create_new_folder_outlined, size: 16),
              label: const Text('Add project'),
            ),
          ],
        ),
      );
    }
    final rows = _displayRows(session.items);
    final userTurns = <({int turnIndex, int rowIndex, ChatItem item})>[];
    var turnCounter = 0;
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      if (r is ChatItem && r.kind == ItemKind.user) {
        userTurns.add((turnIndex: turnCounter++, rowIndex: i, item: r));
      }
    }
    final chat = Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.circle,
                size: 8,
                color: session.connected
                    ? theme.colorScheme.secondary
                    : theme.hintColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${_folderName(session.projectDir)} — ${session.status}'
                  '${session.worktreeBranch != null ? ' · ${session.worktreeBranch}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
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
                          _railTab = _RailTab.review;
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
                                text: '+${_formatCount(session.diffAdditions)}',
                                style: const TextStyle(
                                  color: Color(0xFF5EA86D),
                                ),
                              ),
                              const TextSpan(text: '  '),
                              TextSpan(
                                text: '-${_formatCount(session.diffDeletions)}',
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                ),
                              ),
                            ],
                          ),
                          style: theme.textTheme.labelSmall
                              ?.copyWith(fontFamily: 'GeistMono'),
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
                onPressed: () =>
                    setState(() => _showRail = !_showRail),
                icon: Icon(
                  _showRail
                      ? Icons.view_sidebar
                      : Icons.view_sidebar_outlined,
                  size: 18,
                ),
                tooltip: 'Toggle panel',
              ),
              if (session.streaming)
                TextButton.icon(
                  onPressed: session.abort,
                  icon: const Icon(Icons.stop, size: 16),
                  label: const Text('Stop'),
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
                  ? const _TranscriptSkeleton()
                  : session.items.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                '✳',
                                style: TextStyle(
                                  fontSize: 26,
                                  color: Color(0xFFE5855E),
                                  height: 1,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    const TextSpan(
                                        text: 'What should we build in '),
                                    TextSpan(
                                      text: _folderName(session.projectDir),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
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
                            if (userTurns.length >= 2)
                              Padding(
                                padding:
                                    const EdgeInsets.only(top: 22, right: 6),
                                child: _TurnScrubber(
                                  turns: userTurns,
                                  activeTurn: _activeTurn,
                                  onSelectTurn: (turnIndex) async {
                                    setState(() => _activeTurn = turnIndex);
                                    _isProgrammaticScroll = true;
                                    final key = _turnKeys[turnIndex];
                                    if (key?.currentContext != null) {
                                      await Scrollable.ensureVisible(
                                        key!.currentContext!,
                                        duration:
                                            const Duration(milliseconds: 300),
                                        curve: Curves.easeOutCubic,
                                        alignment: 0.05,
                                      );
                                    } else if (_scroll.hasClients &&
                                        _scroll.position.maxScrollExtent > 0) {
                                      final turn = userTurns.firstWhere(
                                        (t) => t.turnIndex == turnIndex,
                                      );
                                      final ratio = rows.length > 1
                                          ? turn.rowIndex / (rows.length - 1)
                                          : 0.0;
                                      final target = (ratio *
                                              _scroll.position.maxScrollExtent)
                                          .clamp(
                                        0.0,
                                        _scroll.position.maxScrollExtent,
                                      );
                                      await _scroll.animateTo(
                                        target,
                                        duration:
                                            const Duration(milliseconds: 300),
                                        curve: Curves.easeOutCubic,
                                      );
                                      // Row heights vary wildly (code blocks,
                                      // diffs), so a ratio estimate lands short
                                      // or long. The target is inside the cache
                                      // window now, so correct against its real
                                      // offset instead of leaving it approximate.
                                      await WidgetsBinding.instance.endOfFrame;
                                      final landed = key?.currentContext;
                                      if (landed != null && landed.mounted) {
                                        await Scrollable.ensureVisible(
                                          landed,
                                          duration: const Duration(
                                            milliseconds: 160,
                                          ),
                                          curve: Curves.easeOutCubic,
                                          alignment: 0.05,
                                        );
                                      }
                                    }
                                    await Future.delayed(
                                      const Duration(milliseconds: 100),
                                    );
                                    _isProgrammaticScroll = false;
                                  },
                                ),
                              ),
                            Expanded(
                              child: NotificationListener<ScrollNotification>(
                                onNotification: (notification) {
                                  if (notification.metrics.pixels <= 160) {
                                    _maybeLoadOlder(session);
                                  }
                                  if (!_isProgrammaticScroll &&
                                      userTurns.length >= 2 &&
                                      notification.metrics.maxScrollExtent > 0) {
                                    int? closest;
                                    double minDistance = double.infinity;
                                    for (final t in userTurns) {
                                      final key = _turnKeys[t.turnIndex];
                                      final ctx = key?.currentContext;
                                      if (ctx != null) {
                                        final box =
                                            ctx.findRenderObject() as RenderBox?;
                                        if (box != null && box.hasSize) {
                                          final dy =
                                              box.localToGlobal(Offset.zero).dy;
                                          final dist = (dy - 120).abs();
                                          if (dist < minDistance) {
                                            minDistance = dist;
                                            closest = t.turnIndex;
                                          }
                                        }
                                      }
                                    }
                                    if (closest != null &&
                                        closest != _activeTurn) {
                                      setState(() => _activeTurn = closest!);
                                    }
                                  }
                                  return false;
                                },
                                child: ListView.builder(
                                  controller: _scroll,
                                  // Was 50000px, which kept almost every row of
                                  // a long session built and laid out on every
                                  // scroll frame. Each markdown block is a
                                  // SelectableText — a live EditableText with
                                  // its own selection machinery — so hundreds
                                  // of them alive made the transcript advance in
                                  // visible jumps. A screen of slack above and
                                  // below is enough for smooth scroll-back, and
                                  // turn jumps correct themselves (see below).
                                  scrollCacheExtent:
                                      const ScrollCacheExtent.pixels(1200.0),
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 16, 16, 24),
                                  itemCount: rows.length,
                                  itemBuilder: (context, index) {
                                    final row = rows[index];
                                    if (row is List<ChatItem>) {
                                      return _ActivityBlockView(
                                        items: row,
                                        live: session.streaming &&
                                            index == rows.length - 1,
                                        seconds: session.processingSeconds,
                                        tokensPerSecond:
                                            session.tokensPerSecond,
                                      );
                                    }
                                    final item = row as ChatItem;
                                    Key? key;
                                    if (item.kind == ItemKind.user) {
                                      final turnIdx = userTurns.indexWhere(
                                        (t) => identical(t.item, item),
                                      );
                                      if (turnIdx != -1) {
                                        key = _turnKeys.putIfAbsent(
                                          turnIdx,
                                          () => GlobalKey(),
                                        );
                                      }
                                    }
                                    return _ChatItemView(
                                      item,
                                      key: key,
                                      live: session.streaming &&
                                          item.kind == ItemKind.assistant &&
                                          index == rows.length - 1,
                                    );
                                  },
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
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: theme.dividerColor.withValues(alpha: 0.5),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Focus(
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
                              hintText:
                                  'Ask anything, @ to add files, or / for commands',
                              border: InputBorder.none,
                              filled: false,
                              isDense: true,
                              contentPadding:
                                  EdgeInsets.symmetric(vertical: 10),
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
                            _AccessPill(session: session),
                            const Spacer(),
                            if (session.streaming) ...[
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 12),
                            ],
                            if (session.isStarted) _ContextRing(session: session),
                            _AgentSettingsMenu(session: session),
                            const SizedBox(width: 8),
                            _SendButton(enabled: true, onTap: _send),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
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
    return chat;
  }
}

/// Small footer chip under the composer: icon + label, interactive when given
/// an [onTap].
class _FooterChip extends StatelessWidget {
  const _FooterChip({
    required this.icon,
    required this.label,
    this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chip = _HoverTint(
      radius: 6,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: theme.hintColor),
            const SizedBox(width: 5),
            Text(
              label,
              style:
                  theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
            ),
          ],
        ),
      ),
    );
    final message = tooltip;
    return message == null ? chip : Tooltip(message: message, child: chip);
  }
}

/// Review tab: changed files with per-file counts and a line-numbered diff,
/// shaped like the reference review pane.
class _DiffView extends StatefulWidget {
  const _DiffView({required this.workingDirectory, super.key});

  final String workingDirectory;

  @override
  State<_DiffView> createState() => _DiffViewState();
}

class _DiffViewState extends State<_DiffView> {
  List<({String path, String status, int additions, int deletions})> _files =
      [];
  String? _selected;
  List<DiffLine> _lines = [];
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final files = await changedFiles(widget.workingDirectory);
    var selected = _selected;
    if (selected == null || !files.any((file) => file.path == selected)) {
      selected = files.isEmpty ? null : files.first.path;
    }
    var lines = <DiffLine>[];
    if (selected != null) {
      lines = parseUnifiedDiff(
        await fileDiff(widget.workingDirectory, selected),
      );
    }
    if (!mounted) return;
    setState(() {
      _files = files;
      _selected = selected;
      _lines = lines;
      _loading = false;
    });
  }

  Future<void> _select(String path) async {
    setState(() {
      _selected = path;
      _loading = true;
    });
    final lines = parseUnifiedDiff(
      await fileDiff(widget.workingDirectory, path),
    );
    if (!mounted) return;
    setState(() {
      _lines = lines;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final additions = _files.fold<int>(0, (sum, file) => sum + file.additions);
    final deletions = _files.fold<int>(0, (sum, file) => sum + file.deletions);
    ({String path, String status, int additions, int deletions})? selected;
    for (final file in _files) {
      if (file.path == _selected) {
        selected = file;
        break;
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
          child: Row(
            children: [
              Text(
                'Uncommitted',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              Text(
                '+${_formatCount(additions)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF5EA86D),
                  fontFamily: 'GeistMono',
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '-${_formatCount(deletions)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontFamily: 'GeistMono',
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh, size: 15),
                tooltip: 'Reload',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _loading
              ? const _TranscriptSkeleton()
              : _files.isEmpty
                  ? Center(
                      child: Text(
                        'No changes.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.hintColor),
                      ),
                    )
                  : Row(
                      children: [
                        Expanded(child: _diffPane(theme, selected)),
                        const VerticalDivider(width: 1),
                        SizedBox(width: 180, child: _fileList(theme)),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _diffPane(
    ThemeData theme,
    ({String path, String status, int additions, int deletions})? selected,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selected != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selected.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(fontFamily: 'GeistMono'),
                  ),
                ),
                Text(
                  '+${_formatCount(selected.additions)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF5EA86D),
                    fontFamily: 'GeistMono',
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '-${_formatCount(selected.deletions)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontFamily: 'GeistMono',
                  ),
                ),
              ],
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _lines.length,
            itemBuilder: (context, index) => _diffLineRow(theme, _lines[index]),
          ),
        ),
      ],
    );
  }

  Widget _diffLineRow(ThemeData theme, DiffLine line) {
    final green = const Color(0xFF5EA86D);
    final numberStyle = theme.textTheme.labelSmall?.copyWith(
      fontFamily: 'GeistMono',
      fontSize: 11.5,
      height: 1.45,
      color: theme.hintColor.withValues(alpha: 0.65),
    );
    var codeStyle = TextStyle(
      fontFamily: 'GeistMono',
      fontSize: 12.5,
      height: 1.45,
      color: theme.colorScheme.onSurface,
    );
    Color? background;
    switch (line.kind) {
      case DiffLineKind.add:
        background = green.withValues(alpha: 0.09);
      case DiffLineKind.remove:
        background = theme.colorScheme.error.withValues(alpha: 0.11);
      case DiffLineKind.hunk:
        background = theme.colorScheme.surfaceContainerHigh;
        codeStyle = codeStyle.copyWith(color: theme.hintColor);
      case DiffLineKind.meta:
        codeStyle = codeStyle.copyWith(color: theme.hintColor);
      case DiffLineKind.context:
        break;
    }
    return Container(
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 30,
            child: Text(
              line.oldNo?.toString() ?? '',
              textAlign: TextAlign.right,
              style: numberStyle,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 30,
            child: Text(
              line.newNo?.toString() ?? '',
              textAlign: TextAlign.right,
              style: numberStyle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(line.text, style: codeStyle)),
        ],
      ),
    );
  }

  Widget _fileList(ThemeData theme) {
    final green = const Color(0xFF5EA86D);
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        final name = file.path.split('/').last;
        final separator = file.path.lastIndexOf('/');
        final dir =
            separator > 0 ? file.path.substring(0, separator) : '';
        final selected = file.path == _selected;
        final statusColor = switch (file.status) {
          'A' || '??' => green,
          'D' => theme.colorScheme.error,
          '?' => theme.hintColor,
          _ => theme.colorScheme.primary,
        };
        return _HoverTint(
          radius: 0,
          alpha: 0.07,
          baseColor: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : null,
          onTap: () => _select(file.path),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 14,
                  child: Text(
                    file.status,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      if (dir.isNotEmpty)
                        Text(
                          dir,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.hintColor),
                        ),
                    ],
                  ),
                ),
                if (file.additions > 0)
                  Text(
                    '+${file.additions}',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: green, fontFamily: 'GeistMono'),
                  ),
                if (file.deletions > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '-${file.deletions}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontFamily: 'GeistMono',
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// File tree for the Files tab: expandable folders, click a file to open it
/// in the OS default editor.
class _FileTree extends StatefulWidget {
  const _FileTree({required this.root});

  final String root;

  @override
  State<_FileTree> createState() => _FileTreeState();
}

class _FileTreeState extends State<_FileTree> {
  final _expanded = <String>{};
  final _cache = <String, List<FileSystemEntity>>{};

  @override
  void initState() {
    super.initState();
    _expanded.add(widget.root);
    _load(widget.root);
  }

  void _load(String path) {
    if (_cache.containsKey(path)) return;
    try {
      final entries = Directory(path).listSync(followLinks: false)
        ..sort((a, b) {
          final aDir = a is Directory;
          final bDir = b is Directory;
          if (aDir != bDir) return aDir ? -1 : 1;
          return a.path.toLowerCase().compareTo(b.path.toLowerCase());
        });
      _cache[path] = entries;
    } on FileSystemException {
      _cache[path] = const [];
    }
  }

  void _toggle(String path) {
    setState(() {
      if (_expanded.contains(path)) {
        _expanded.remove(path);
      } else {
        _expanded.add(path);
        _load(path);
      }
    });
  }

  void _openFile(String path) => Process.start('explorer', [path]);

  List<Widget> _rows(String path, int depth) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];
    for (final entry in _cache[path] ?? const <FileSystemEntity>[]) {
      final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final isDir = entry is Directory;
      final expanded = _expanded.contains(entry.path);
      widgets.add(
        _HoverTint(
          radius: 0,
          alpha: 0.07,
          onTap: () => isDir ? _toggle(entry.path) : _openFile(entry.path),
          child: Padding(
            padding: EdgeInsets.fromLTRB(10 + depth * 12.0, 4, 8, 4),
            child: Row(
              children: [
                Icon(
                  isDir
                      ? (expanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_right)
                      : Icons.description_outlined,
                  size: 14,
                  color: theme.hintColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (isDir && expanded) widgets.addAll(_rows(entry.path, depth + 1));
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: _rows(widget.root, 0),
    );
  }
}

/// Terminal tab: runs commands in the project folder and shows their output.
/// A command runner rather than a full PTY — enough for git/build/test loops.
class _TerminalPanel extends StatefulWidget {
  const _TerminalPanel({required this.workingDirectory});

  final String workingDirectory;

  @override
  State<_TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<_TerminalPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _entries = <({String command, String output, int code})>[];
  var _running = false;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final command = _input.text.trim();
    if (command.isEmpty || _running) return;
    _input.clear();
    setState(() {
      _running = true;
      _entries.add((command: command, output: '', code: 0));
    });
    _scrollToEnd();
    try {
      final result = await Process.run(
        command,
        const [],
        workingDirectory: widget.workingDirectory,
        runInShell: true,
      );
      if (!mounted) return;
      setState(() {
        _entries[_entries.length - 1] = (
          command: command,
          output: '${result.stdout}${result.stderr}',
          code: result.exitCode,
        );
        _running = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _entries[_entries.length - 1] =
            (command: command, output: '$error', code: -1);
        _running = false;
      });
    }
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: _entries.isEmpty
              ? Center(
                  child: Text(
                    'Run commands in ${widget.workingDirectory}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor),
                  ),
                )
              : ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(10),
                  children: [
                    for (final entry in _entries) ...[
                      Row(
                        children: [
                          Text(
                            '\$ ',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontFamily: 'GeistMono',
                            ),
                          ),
                          Expanded(
                            child: Text(
                              entry.command,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(fontFamily: 'GeistMono'),
                            ),
                          ),
                          if (entry.code != 0)
                            Text(
                              'exit ${entry.code}',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: theme.colorScheme.error),
                            ),
                        ],
                      ),
                      if (entry.output.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 10),
                          child: _CodeBox(entry.output.trim()),
                        ),
                    ],
                    if (_running)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                  ],
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  autofocus: true,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFamily: 'GeistMono'),
                  decoration: const InputDecoration(
                    hintText: 'git status',
                    filled: false,
                    isDense: true,
                  ),
                  onSubmitted: (_) => _run(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _running ? null : _run,
                icon: const Icon(Icons.play_arrow, size: 18),
                tooltip: 'Run',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Fade-in with an optional stagger delay, used for list reveals.
/// Plays once per element and collapses under reduced motion.
class _FadeIn extends StatefulWidget {
  const _FadeIn({required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<_FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<_FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) _controller.value = 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
      child: widget.child,
    );
  }
}

/// Fade + 6px rise on first appearance. Motivated by content arriving;
/// runs once per item and collapses under reduced motion.
class _Appear extends StatefulWidget {
  const _Appear({required this.item, required this.child, this.offset = 6});

  final ChatItem item;
  final Widget child;
  final double offset;

  @override
  State<_Appear> createState() => _AppearState();
}

class _AppearState extends State<_Appear> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 190),
  );

  @override
  void initState() {
    super.initState();
    if (widget.item.animated) {
      _controller.value = 1;
    } else {
      widget.item.animated = true;
      _controller.forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) _controller.value = 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved =
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, widget.offset * (1 - curved.value)),
          child: child,
        ),
        child: widget.child,
      ),
    );
  }
}

/// Draggable pane splitter: 8px hit area, hover highlight, double-click reset.
class _SplitHandle extends StatefulWidget {
  const _SplitHandle({required this.onDrag, required this.onReset});

  final ValueChanged<double> onDrag;
  final VoidCallback onReset;

  @override
  State<_SplitHandle> createState() => _SplitHandleState();
}

class _SplitHandleState extends State<_SplitHandle> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
        onDoubleTap: widget.onReset,
        child: AnimatedContainer(
          duration: _motion(context, 90),
          width: 8,
          color: _hovered
              ? theme.colorScheme.primary.withValues(alpha: 0.35)
              : Colors.transparent,
        ),
      ),
    );
  }
}

/// One flat session row: title, then project + age, with hover/selection
/// states and a menu that only appears when the row is hovered or selected.
class _SessionRow extends StatefulWidget {
  const _SessionRow({
    required this.title,
    required this.folder,
    required this.time,
    required this.status,
    required this.selected,
    required this.onTap,
    required this.menu,
  });

  final String title;
  final String folder;
  final DateTime? time;
  final _CardStatus status;
  final bool selected;
  final VoidCallback onTap;
  final Widget menu;

  @override
  State<_SessionRow> createState() => _SessionRowState();
}

class _SessionRowState extends State<_SessionRow> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = widget.selected
        ? theme.colorScheme.primary.withValues(alpha: 0.12)
        : (_hovered ? theme.colorScheme.onSurface.withValues(alpha: 0.05) : null);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 1),
        child: AnimatedContainer(
          duration: _motion(context),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: background ?? Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 7, 6, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 14,
                        child: widget.status == _CardStatus.running
                            ? const SizedBox(
                                width: 11,
                                height: 11,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : widget.status == _CardStatus.unread
                                ? Icon(
                                    Icons.circle,
                                    size: 7,
                                    color: theme.colorScheme.primary,
                                  )
                                : null,
                      ),
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: widget.selected
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurface
                                    .withValues(alpha: 0.92),
                          ),
                        ),
                      ),
                      if (_hovered || widget.selected)
                        widget.menu
                      else
                        const SizedBox(width: 4),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          widget.folder,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.hintColor),
                        ),
                      ),
                      if (widget.time != null)
                        Text(
                          _relativeTime(widget.time!),
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.hintColor),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatItemView extends StatefulWidget {
  const _ChatItemView(this.item, {super.key, this.live = false});

  final ChatItem item;

  /// True for the assistant message that tokens are still arriving in.
  final bool live;

  @override
  State<_ChatItemView> createState() => _ChatItemViewState();
}

class _ChatItemViewState extends State<_ChatItemView> {
  Widget? _cached;

  // Compared by identity: ChatItem is mutated in place as tokens and tool
  // results land, so a changed field shows up as a new String instance.
  ChatItem? _item;
  Object? _text;
  Object? _result;
  bool _done = false;
  bool _errored = false;
  bool _live = false;

  /// [_item] guards against the builder reusing this element for a different
  /// row — which happens when older history is prepended and indices shift.
  bool get _unchanged =>
      identical(_item, widget.item) &&
      identical(_text, widget.item.text) &&
      identical(_result, widget.item.result) &&
      _done == widget.item.isDone &&
      _errored == widget.item.isError &&
      _live == widget.live;

  @override
  Widget build(BuildContext context) {
    // A streaming turn notifies the whole page ~16x/second. Handing back the
    // identical widget for every settled row lets Flutter skip those subtrees,
    // which keeps markdown re-parsing to the single message that changed.
    if (_cached != null && _unchanged) return _cached!;
    _item = widget.item;
    _text = widget.item.text;
    _result = widget.item.result;
    _done = widget.item.isDone;
    _errored = widget.item.isError;
    _live = widget.live;
    return _cached = _Appear(
      item: widget.item,
      child: _body(context, Theme.of(context)),
    );
  }

  Widget _body(BuildContext context, ThemeData theme) {
    final item = widget.item;
    switch (item.kind) {
      case ItemKind.user:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 640),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: SelectableText(item.text),
                ),
              ),
              if (item.time != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3, right: 4),
                  child: Text(
                    _formatTime(item.time!),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.hintColor),
                  ),
                ),
            ],
          ),
        );
      case ItemKind.assistant:
        return _AssistantMessageView(item: item, live: widget.live);
      case ItemKind.event:
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 14,
                color: theme.hintColor,
              ),
              const SizedBox(width: 8),
              Text(
                item.text,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        );
      case ItemKind.thinking:
        // Thinking normally renders inside an activity block; this is a
        // fallback for a stray block-less thinking item.
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SelectableText(
            item.text,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
        );
      case ItemKind.tool:
        final args = item.args?.trim() ?? '';
        final result = item.result?.trim() ?? '';
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            title: Row(
              children: [
                Icon(
                  item.isError
                      ? Icons.error_outline
                      : (item.isDone
                          ? Icons.build_circle_outlined
                          : Icons.build_outlined),
                  size: 16,
                  color: item.isError ? theme.colorScheme.error : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.toolName.isEmpty ? 'tool' : item.toolName,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
              ],
            ),
            subtitle: result.isEmpty
                ? null
                : Text(
                    result.split('\n').first,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor),
                  ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              if (args.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Arguments', style: theme.textTheme.labelSmall),
                ),
                const SizedBox(height: 4),
                _CodeBox(args),
              ],
              if (args.isNotEmpty && result.isNotEmpty)
                const SizedBox(height: 12),
              if (result.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    item.isError ? 'Error' : 'Result',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
                const SizedBox(height: 4),
                _CodeBox(result),
              ],
            ],
          ),
        );
      case ItemKind.notice:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Center(
            child: Text(
              item.text,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.hintColor),
            ),
          ),
        );
    }
  }
}

class _AssistantMessageView extends StatefulWidget {
  const _AssistantMessageView({required this.item, this.live = false});

  final ChatItem item;

  /// True while this message is the one still being written.
  final bool live;

  @override
  State<_AssistantMessageView> createState() => _AssistantMessageViewState();
}

class _AssistantMessageViewState extends State<_AssistantMessageView> {
  var _hovered = false;
  var _copied = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MarkdownBody(
              data: widget.item.text,
              selectable: true,
              styleSheet: _markdownStyleSheet(theme),
            ),
            // A caret under the growing text: without it a slow turn looks
            // like a finished message rather than one still being written.
            if (widget.live)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: _StreamCaret(color: theme.colorScheme.primary),
              ),
            const SizedBox(height: 4),
            AnimatedOpacity(
              opacity: _hovered ? 1.0 : 0.0,
              duration: _motion(context, 100),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () {
                      Clipboard.setData(
                        ClipboardData(text: widget.item.text),
                      );
                      setState(() => _copied = true);
                      Future.delayed(const Duration(seconds: 2), () {
                        if (mounted) setState(() => _copied = false);
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _copied ? Icons.check : Icons.copy_outlined,
                            size: 13,
                            color: _copied
                                ? theme.colorScheme.primary
                                : theme.hintColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _copied ? 'Copied' : 'Copy',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: _copied
                                  ? theme.colorScheme.primary
                                  : theme.hintColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (widget.item.time != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      _formatTime(widget.item.time!),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.hintColor),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessPill extends StatefulWidget {
  const _AccessPill({required this.session});

  final SessionController session;

  @override
  State<_AccessPill> createState() => _AccessPillState();
}

class _AccessPillState extends State<_AccessPill> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final full = widget.session.fullAccess;
    return Tooltip(
      message: full
          ? 'Full access: auto-executes tools'
          : 'Ask first: confirms tool calls',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.session.toggleAccess,
          child: AnimatedContainer(
            duration: _motion(context, 120),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            // The pill paints its own background, so an Ink splash on the
            // Material behind it would be hidden — animate the fill instead.
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: _hovered ? 0.75 : 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _hovered
                    ? theme.colorScheme.outline.withValues(alpha: 0.45)
                    : theme.dividerColor,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  full ? Icons.lock_open_outlined : Icons.pan_tool_outlined,
                  size: 13,
                  color:
                      full ? theme.colorScheme.secondary : theme.hintColor,
                ),
                const SizedBox(width: 5),
                Text(
                  full ? 'Full access' : 'Ask first',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: full
                        ? theme.colorScheme.onSurface
                        : theme.hintColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Vertical timeline scrubber matching the turn navigator from the reference.
/// Subtle tick marks on the left; active turn is wider and brighter.
/// Tap jumps to that turn; hover displays the prompt preview.
class _TurnScrubber extends StatelessWidget {
  const _TurnScrubber({
    required this.turns,
    required this.activeTurn,
    required this.onSelectTurn,
  });

  final List<({int turnIndex, int rowIndex, ChatItem item})> turns;
  final int activeTurn;
  final ValueChanged<int> onSelectTurn;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final turn in turns)
          _ScrubberTick(
            turn: turn,
            isActive: turn.turnIndex == activeTurn,
            onTap: () => onSelectTurn(turn.turnIndex),
          ),
      ],
    );
  }
}

class _ScrubberTick extends StatefulWidget {
  const _ScrubberTick({
    required this.turn,
    required this.isActive,
    required this.onTap,
  });

  final ({int turnIndex, int rowIndex, ChatItem item}) turn;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_ScrubberTick> createState() => _ScrubberTickState();
}

class _ScrubberTickState extends State<_ScrubberTick> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snippet =
        widget.turn.item.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final preview =
        snippet.length <= 60 ? snippet : '${snippet.substring(0, 60)}…';
    final time = widget.turn.item.time != null
        ? ' · ${_formatTime(widget.turn.item.time!)}'
        : '';

    final width = widget.isActive ? 18.0 : (_hovered ? 14.0 : 8.0);
    final color = widget.isActive
        ? theme.colorScheme.onSurface
        : (_hovered
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.outlineVariant.withValues(alpha: 0.5));

    return Tooltip(
      message: '$preview$time',
      waitDuration: const Duration(milliseconds: 150),
      child: InkWell(
        borderRadius: BorderRadius.circular(2),
        onTap: widget.onTap,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 3.5, horizontal: 2),
            child: AnimatedContainer(
              duration: _motion(context, 120),
              curve: Curves.easeOutCubic,
              width: width,
              height: widget.isActive ? 2.5 : 2.0,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CodeBox extends StatelessWidget {
  const _CodeBox(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 320),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: SingleChildScrollView(
        child: SelectableText(
          text,
          style: const TextStyle(fontSize: 13.5, fontFamily: 'GeistMono'),
        ),
      ),
    );
  }
}

/// One agent turn: a "Processing 2m 20s · 76 token/s" header, one-line steps,
/// and a pulsing status line while running. Collapses to a summary otherwise.
class _ActivityBlockView extends StatefulWidget {
  const _ActivityBlockView({
    required this.items,
    required this.live,
    required this.seconds,
    required this.tokensPerSecond,
  });

  final List<ChatItem> items;
  final bool live;
  final int seconds;
  final double? tokensPerSecond;

  @override
  State<_ActivityBlockView> createState() => _ActivityBlockViewState();
}

class _ActivityBlockViewState extends State<_ActivityBlockView> {
  var _expanded = false;

  bool get _hasError => widget.items.any((item) => item.isError);

  @override
  void didUpdateWidget(_ActivityBlockView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.live && !widget.live) {
      // Turn finished: collapse back to the summary line.
      setState(() => _expanded = false);
    }
  }

  String get _summary {
    var thoughts = 0;
    var viewed = 0;
    var commands = 0;
    var edited = 0;
    var other = 0;
    for (final item in widget.items) {
      final name = item.toolName.toLowerCase();
      if (item.kind == ItemKind.thinking) {
        thoughts++;
      } else if (name == 'bash' || name == 'shell') {
        commands++;
      } else if (const {
        'read',
        'grep',
        'glob',
        'search',
        'fetch',
        'webfetch',
        'web_search',
      }.contains(name)) {
        viewed++;
      } else if (const {'edit', 'write', 'multiedit'}.contains(name)) {
        edited++;
      } else {
        other++;
      }
    }
    final parts = <String>[];
    if (thoughts > 0) parts.add('Thought $thoughts time(s)');
    if (viewed > 0) parts.add('Viewed $viewed file(s)');
    if (commands > 0) parts.add('Ran $commands command(s)');
    if (edited > 0) parts.add('Edited $edited file(s)');
    if (other > 0) parts.add('Used $other tool(s)');
    return parts.isEmpty ? 'Worked' : parts.join(', ');
  }

  String get _statusLabel {
    if (widget.items.isEmpty) return 'Working';
    final last = widget.items.last;
    if (last.kind == ItemKind.thinking) return 'Thinking';
    final name = last.toolName.toLowerCase();
    if (name == 'bash' || name == 'shell') return 'Running command';
    if (name == 'read') return 'Reading file';
    if (name == 'edit' || name == 'write') return 'Editing file';
    if (name == 'grep' || name == 'glob' || name == 'search') {
      return 'Searching';
    }
    return last.toolName.isEmpty ? 'Working' : last.toolName;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final running = widget.live;
    final steps = widget.items;
    final dim = theme.textTheme.labelSmall?.copyWith(color: theme.hintColor);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (running) ...[
            Row(
              children: [
                Text(
                  'Processing ${_formatDuration(widget.seconds)}',
                  style: dim,
                ),
                const Spacer(),
                if (widget.tokensPerSecond != null)
                  Text(
                    '${widget.tokensPerSecond!.round()} token/s',
                    style: dim,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Divider(height: 1, color: theme.dividerColor),
            const SizedBox(height: 6),
          ],
          if (!running)
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  Icon(
                    _hasError
                        ? Icons.error_outline
                        : Icons.check_circle_outline,
                    size: 14,
                    color:
                        _hasError ? theme.colorScheme.error : theme.hintColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _summary,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: _hasError
                            ? theme.colorScheme.error
                            : theme.hintColor,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 15,
                    color: theme.hintColor,
                  ),
                ],
              ),
            ),
          if (_expanded)
            AnimatedSize(
              duration: _motion(context, 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in steps)
                    _Appear(
                      item: item,
                      offset: 4,
                      child: _StepRow(item),
                    ),
                ],
              ),
            )
          else if (running && steps.isNotEmpty)
            _Appear(
              item: steps.last,
              offset: 4,
              child: _StepRow(steps.last),
            ),
          if (running) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const _PulseBars(),
                const SizedBox(width: 8),
                Text(
                  '$_statusLabel…',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One line of the activity feed: icon, label, expandable detail.
class _StepRow extends StatefulWidget {
  const _StepRow(this.item);

  final ChatItem item;

  @override
  State<_StepRow> createState() => _StepRowState();
}

class _StepRowState extends State<_StepRow> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    final detail = item.kind == ItemKind.thinking
        ? item.text.trim()
        : (item.result ?? '').trim();
    final hasDetail = detail.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: hasDetail ? () => setState(() => _open = !_open) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Icon(
                  _stepIcon(item),
                  size: 14,
                  color: item.isError ? theme.colorScheme.error : theme.hintColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _stepLabel(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: item.isError
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (hasDetail)
                  Icon(
                    _open ? Icons.expand_less : Icons.chevron_right,
                    size: 14,
                    color: theme.hintColor,
                  ),
              ],
            ),
          ),
        ),
        if (_open && hasDetail)
          Padding(
            padding: const EdgeInsets.only(left: 22, top: 2, bottom: 8),
            child: item.kind == ItemKind.thinking
                ? SelectableText(
                    detail,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.hintColor),
                  )
                : _CodeBox(detail),
          ),
      ],
    );
  }
}

IconData _stepIcon(ChatItem item) {
  if (item.kind == ItemKind.thinking) return Icons.psychology_outlined;
  switch (item.toolName.toLowerCase()) {
    case 'bash':
    case 'shell':
      return Icons.terminal;
    case 'read':
      return Icons.description_outlined;
    case 'edit':
    case 'write':
    case 'multiedit':
      return Icons.edit_outlined;
    case 'grep':
    case 'glob':
    case 'search':
      return Icons.search;
    case 'todo':
    case 'todowrite':
      return Icons.checklist;
    default:
      return Icons.build_outlined;
  }
}

String _stepLabel(ChatItem item) {
  if (item.kind == ItemKind.thinking) {
    final first = item.text.trim().split('\n').first;
    return first.isEmpty ? 'Thinking process' : first;
  }
  final name = item.toolName.toLowerCase();
  final args = _toolArgs(item);
  switch (name) {
    case 'bash':
    case 'shell':
      final command = args?['command'];
      return command is String ? command : 'Ran command';
    case 'read':
      final path = args?['path'];
      return path is String ? 'Read file ${_baseName(path)}' : 'Read file';
    case 'edit':
    case 'write':
    case 'multiedit':
      final path = args?['path'];
      return path is String ? 'Edit ${_baseName(path)}' : 'Edit file';
    case 'grep':
    case 'glob':
    case 'search':
      final pattern = args?['pattern'] ?? args?['query'];
      return pattern is String ? 'Search "$pattern"' : 'Search';
    case 'todo':
    case 'todowrite':
      return 'Update todos';
    default:
      final detail = args?['path'] ?? args?['file_path'] ?? args?['query'];
      final suffix = detail is String ? ' ${_baseName(detail)}' : '';
      return '${item.toolName.isEmpty ? 'Tool' : item.toolName}$suffix';
  }
}

Map<String, dynamic>? _toolArgs(ChatItem item) {
  final args = item.args;
  if (args == null || args.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(args);
    return decoded is Map<String, dynamic> ? decoded : null;
  } on FormatException {
    return null;
  }
}

String _baseName(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}

/// Three tiny bars pulsing like a live activity indicator.
class _PulseBars extends StatefulWidget {
  const _PulseBars();

  @override
  State<_PulseBars> createState() => _PulseBarsState();
}

class _PulseBarsState extends State<_PulseBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduce = MediaQuery.of(context).disableAnimations;
    return SizedBox(
      width: 16,
      height: 13,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = reduce ? 0.5 : _controller.value;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 3,
                  height: 4 + _wave((t + i * 0.22) % 1) * 9,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static double _wave(double phase) =>
      phase < 0.5 ? phase * 2 : (1 - phase) * 2;
}

String _formatDuration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  if (minutes < 60) return '${minutes}m ${rest}s';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

String _formatTime(DateTime time) {
  final local = time.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// Context-window ring; click opens the session stats menu anchored to it.
class _ContextRing extends StatefulWidget {
  const _ContextRing({required this.session});

  final SessionController session;

  @override
  State<_ContextRing> createState() => _ContextRingState();
}

class _ContextRingState extends State<_ContextRing> {
  final _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = widget.session;
    final usage = session.stats?['contextUsage'];
    final percent = usage is Map && usage['percent'] is num
        ? (usage['percent'] as num).toDouble()
        : null;
    final color = percent != null && percent >= 85
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    return MenuAnchor(
      controller: _controller,
      menuChildren: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            width: 300,
            child: ListenableBuilder(
              listenable: session,
              builder: (context, _) => _StatsTable(session: session),
            ),
          ),
        ),
        const Divider(height: 1),
      ],
      builder: (context, controller, child) => Tooltip(
        message: percent == null
            ? 'Context usage'
            : 'Context ${percent.toStringAsFixed(0)}%',
        child: _HoverTint(
          radius: 20,
          alpha: 0.08,
          onTap: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              // Always fetch fresh numbers when opening.
              session.refreshStats();
              controller.open();
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                value: percent == null ? 0 : (percent / 100).clamp(0.0, 1.0),
                strokeWidth: 3,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatsTable extends StatelessWidget {
  const _StatsTable({required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = session.stats;
    if (stats == null) {
      return Text(
        'No stats yet — send a message first.',
        style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
      );
    }
    final rows = <Widget>[];
    void add(String label, String value) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 108,
              child: Text(
                label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor),
              ),
            ),
            Expanded(
              child: Text(value, style: theme.textTheme.bodyMedium),
            ),
          ],
        ),
      ));
    }

    final usage = stats['contextUsage'];
    if (usage is Map) {
      final percent = usage['percent'];
      add(
        'Context',
        '${_formatCount(usage['tokens'])} / ${_formatCount(usage['contextWindow'])} tokens'
        '${percent is num ? '  (${percent.toStringAsFixed(0)}%)' : ''}',
      );
    }
    add(
      'Messages',
      '${_formatCount(stats['totalMessages'])} '
      '(${_formatCount(stats['userMessages'])} user · '
      '${_formatCount(stats['assistantMessages'])} assistant)',
    );
    add(
      'Tool calls',
      '${_formatCount(stats['toolCalls'])} '
      '(${_formatCount(stats['toolResults'])} results)',
    );
    final tokens = stats['tokens'];
    if (tokens is Map) {
      add('Tokens in', _formatCount(tokens['input']));
      add('Tokens out', _formatCount(tokens['output']));
      add('Cache read', _formatCount(tokens['cacheRead']));
      add('Cache write', _formatCount(tokens['cacheWrite']));
      add('Total tokens', _formatCount(tokens['total']));
    }
    final cost = stats['cost'];
    if (cost is num) add('Cost', '\$${cost.toStringAsFixed(4)}');
    final sessionFile = stats['sessionFile'];
    if (sessionFile is String && sessionFile.isNotEmpty) {
      rows.add(_SessionFileRow(path: sessionFile, theme: theme));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: rows,
    );
  }
}

/// Compact relative age: now, 5m, 3h, 2d, 1w, 4mo, 1y.
/// The exact timestamp lives in the row's tooltip.
String _relativeTime(DateTime time) {
  final delta = DateTime.now().difference(time.toLocal());
  if (delta.inMinutes < 1) return 'now';
  if (delta.inHours < 1) return '${delta.inMinutes}m';
  if (delta.inDays < 1) return '${delta.inHours}h';
  if (delta.inDays < 7) return '${delta.inDays}d';
  if (delta.inDays < 30) return '${delta.inDays ~/ 7}w';
  if (delta.inDays < 365) return '${delta.inDays ~/ 30}mo';
  return '${delta.inDays ~/ 365}y';
}

/// Frameless-window title bar: drag anywhere, double-click to maximize,
/// Windows-style minimize/maximize/close on the right.
class _TitleBar extends StatelessWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => beginWindowDrag(),
              onDoubleTap: toggleMaximizeWindow,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(
                    Icons.terminal,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text('Pi Studio', style: theme.textTheme.labelMedium),
                ],
              ),
            ),
          ),
          const _WindowButton(icon: Icons.remove, onTap: minimizeWindow),
          const _WindowButton(
            icon: Icons.crop_square,
            size: 13,
            onTap: toggleMaximizeWindow,
          ),
          const _WindowButton(
            icon: Icons.close,
            onTap: closeWindow,
            close: true,
          ),
        ],
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.onTap,
    this.size = 15,
    this.close = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  /// Close buttons get the Windows-style red hover.
  final bool close;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = !_hovered
        ? Colors.transparent
        : widget.close
            ? const Color(0xFFC42B1C)
            : theme.colorScheme.onSurface.withValues(alpha: 0.08);
    final foreground = _hovered && widget.close
        ? Colors.white
        : theme.colorScheme.onSurfaceVariant;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          width: 46,
          height: 34,
          color: background,
          child: Icon(widget.icon, size: widget.size, color: foreground),
        ),
      ),
    );
  }
}

/// Skeleton placeholder shaped like a transcript, shown while a session loads.
/// Skeletons beat spinners: the layout doesn't jump when content arrives.
class _TranscriptSkeleton extends StatefulWidget {
  const _TranscriptSkeleton();

  @override
  State<_TranscriptSkeleton> createState() => _TranscriptSkeletonState();
}

class _TranscriptSkeletonState extends State<_TranscriptSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduce = MediaQuery.of(context).disableAnimations;
    final base = theme.colorScheme.onSurface.withValues(alpha: 0.06);

    Widget bar(double widthFactor) => Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: widthFactor,
            child: Container(
              height: 12,
              decoration: BoxDecoration(
                color: base,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
          ),
        );

    return FadeTransition(
      opacity: reduce
          ? const AlwaysStoppedAnimation<double>(1)
          : Tween<double>(begin: 0.5, end: 1).animate(
              CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
            ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          bar(0.45),
          const SizedBox(height: 10),
          bar(0.8),
          const SizedBox(height: 10),
          bar(0.6),
          const SizedBox(height: 30),
          bar(0.35),
          const SizedBox(height: 10),
          bar(0.72),
          const SizedBox(height: 10),
          bar(0.5),
        ],
      ),
    );
  }
}

/// Compact session-file row: truncated name, full path on hover, click copies.
class _SessionFileRow extends StatelessWidget {
  const _SessionFileRow({required this.path, required this.theme});

  final String path;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final fileName = path.split(RegExp(r'[\\/]')).last;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              'Session',
              style:
                  theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
          ),
          Expanded(
            child: Tooltip(
              message: path,
              child: _HoverTint(
                radius: 4,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: path));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Session file path copied'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                child: Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatCount(Object? value) {
  if (value is! num) return '–';
  final digits = value.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Custom Markdown stylesheet matching the Geist typography and modern
/// dev-tool hierarchy: clear heading margins, readable line-height,
/// and crisp GeistMono inline/block code.
MarkdownStyleSheet _markdownStyleSheet(ThemeData theme) {
  final base = MarkdownStyleSheet.fromTheme(theme);
  final onSurface = theme.colorScheme.onSurface;
  return base.copyWith(
    h1: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: onSurface,
      height: 1.4,
    ),
    h1Padding: const EdgeInsets.only(top: 24, bottom: 8),
    h2: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      color: onSurface,
      height: 1.4,
    ),
    h2Padding: const EdgeInsets.only(top: 20, bottom: 6),
    h3: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: onSurface,
      height: 1.4,
    ),
    h3Padding: const EdgeInsets.only(top: 14, bottom: 4),
    p: theme.textTheme.bodyMedium?.copyWith(
      fontSize: 14.5,
      height: 1.6,
      color: onSurface.withValues(alpha: 0.92),
    ),
    pPadding: const EdgeInsets.only(bottom: 10),
    listBullet: TextStyle(
      fontSize: 14.5,
      height: 1.5,
      color: theme.hintColor,
    ),
    listBulletPadding: const EdgeInsets.only(right: 8, top: 1),
    code: const TextStyle(
      fontFamily: 'GeistMono',
      fontSize: 13,
      letterSpacing: -0.2,
    ),
    codeblockDecoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: theme.dividerColor),
    ),
    codeblockPadding: const EdgeInsets.all(12),
    blockquoteDecoration: BoxDecoration(
      border: Border(
        left: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.6),
          width: 3,
        ),
      ),
    ),
    blockquotePadding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
    tableBorder: TableBorder.all(color: theme.dividerColor, width: 1),
    tableHead: TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      color: onSurface,
    ),
    tableBody: TextStyle(
      fontSize: 13.5,
      color: onSurface.withValues(alpha: 0.9),
    ),
  );
}

/// Circular send button, like the arrow in the reference composer.
class _SendButton extends StatefulWidget {
  const _SendButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  var _pressed = false;
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = widget.enabled;
    final lifted = enabled && _hovered;
    final duration = _motion(context, 120);

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _pressed ? 0.94 : (lifted ? 1.05 : 1),
        duration: duration,
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: lifted
                ? [
                    BoxShadow(
                      color:
                          theme.colorScheme.primary.withValues(alpha: 0.36),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ]
                : const [],
          ),
          child: Material(
            color: enabled
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTapDown:
                  enabled ? (_) => setState(() => _pressed = true) : null,
              onTapCancel:
                  enabled ? () => setState(() => _pressed = false) : null,
              onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
              onTap: enabled ? widget.onTap : null,
              child: SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                  Icons.arrow_upward,
                  size: 18,
                  color: enabled
                      ? theme.colorScheme.onPrimary
                      : theme.hintColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({required this.label, this.secondary});

  final String label;
  final String? secondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trailing = secondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge,
            ),
          ),
          if (trailing != null)
            Text(
              ' · $trailing',
              style:
                  theme.textTheme.labelLarge?.copyWith(color: theme.hintColor),
            ),
          Icon(Icons.arrow_drop_down, size: 18, color: theme.hintColor),
        ],
      ),
    );
  }
}

/// One menu for model + reasoning effort: reasoning levels first, then
/// models grouped into a submenu per provider.
class _AgentSettingsMenu extends StatefulWidget {
  const _AgentSettingsMenu({required this.session});

  final SessionController session;

  @override
  State<_AgentSettingsMenu> createState() => _AgentSettingsMenuState();
}

class _AgentSettingsMenuState extends State<_AgentSettingsMenu> {
  final _search = TextEditingController();

  /// Model whose reasoning levels are expanded inline in the menu.
  String? _expandedModel;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = widget.session;
    final modelName = session.modelName ??
        (session.isStarted ? 'model' : 'default model');
    final level = session.thinkingLevel;
    final label = level == null ? modelName : '$modelName · $level';

    final byProvider = <String, List<Map<String, dynamic>>>{};
    for (final model in session.models) {
      final provider = '${model['provider'] ?? 'other'}';
      byProvider.putIfAbsent(provider, () => []).add(model);
    }
    for (final models in byProvider.values) {
      models.sort((a, b) =>
          '${a['name'] ?? a['id']}'.compareTo('${b['name'] ?? b['id']}'));
    }
    final providers = byProvider.keys.toList()..sort();

    if (providers.isEmpty && session.thinkingLevels.isEmpty) {
      return _MenuLabel(label: label);
    }

    return MenuAnchor(
      onOpen: () {
        _search.clear();
        _expandedModel = null;
      },
      menuChildren: [
        SizedBox(
          width: 320,
          child: StatefulBuilder(
            builder: (context, setMenuState) {
              final query = _search.text.trim().toLowerCase();
              final matches = session.models
                  .where((model) =>
                      '${model['name'] ?? model['id']}'
                          .toLowerCase()
                          .contains(query) ||
                      '${model['provider'] ?? ''}'
                          .toLowerCase()
                          .contains(query))
                  .toList();

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Search: borderless, separated by a hairline — no filled box.
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: theme.dividerColor),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setMenuState(() {}),
                      style: theme.textTheme.bodySmall,
                      decoration: const InputDecoration(
                        hintText: 'Search models',
                        filled: false,
                        border: InputBorder.none,
                        isDense: true,
                        prefixIcon: Icon(Icons.search, size: 15),
                        prefixIconConstraints: BoxConstraints(
                          minWidth: 26,
                          minHeight: 26,
                        ),
                      ),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: query.isEmpty
                            ? _grouped(
                                session,
                                level,
                                providers,
                                byProvider,
                                setMenuState,
                              )
                            : _searchResults(session, matches),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
      builder: (context, controller, child) => _HoverTint(
        radius: 8,
        alpha: 0.08,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: child ?? const SizedBox.shrink(),
      ),
      child: _MenuLabel(label: modelName, secondary: level),
    );
  }

  List<Widget> _searchResults(
    SessionController session,
    List<Map<String, dynamic>> matches,
  ) {
    final theme = Theme.of(context);
    if (matches.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 22),
          child: Column(
            children: [
              Icon(Icons.search_off, size: 18, color: theme.hintColor),
              const SizedBox(height: 8),
              Text(
                'No models match',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.hintColor),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      for (final model in matches)
        _menuItem(
          selected: '${model['name']}' == session.modelName,
          onPressed: () => session.setModel(
            '${model['provider']}',
            '${model['id']}',
          ),
          child: Row(
            children: [
              Expanded(child: Text('${model['name'] ?? model['id']}')),
              Text(
                '${model['provider'] ?? ''}',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.hintColor),
              ),
            ],
          ),
        ),
    ];
  }

  /// Provider groups separated by hairlines. Selecting a model keeps the menu
  /// open and expands its reasoning levels inline, so model + effort is one
  /// continuous flow instead of two menu visits.
  List<Widget> _grouped(
    SessionController session,
    String? level,
    List<String> providers,
    Map<String, List<Map<String, dynamic>>> byProvider,
    void Function(VoidCallback) setMenuState,
  ) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];
    for (var i = 0; i < providers.length; i++) {
      if (i > 0) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Divider(height: 1, color: theme.dividerColor),
          ),
        );
      }
      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 3),
          child: Text(
            providers[i],
            style:
                theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
          ),
        ),
      );
      for (final model in byProvider[providers[i]]!) {
        final name = '${model['name'] ?? model['id']}';
        final isCurrent = name == session.modelName;
        final hasLevels = session.thinkingLevels.isNotEmpty;
        final expanded = _expandedModel == name;

        widgets.add(
          MenuItemButton(
            // Keep the menu open so the reasoning picker can follow.
            closeOnActivate: false,
            onPressed: () {
              if (!isCurrent) {
                session.setModel('${model['provider']}', '${model['id']}');
              }
              setMenuState(() {
                _expandedModel = expanded ? null : name;
              });
            },
            leadingIcon: Icon(
              Icons.check,
              size: 15,
              color: isCurrent ? theme.colorScheme.primary : Colors.transparent,
            ),
            style: _menuItemStyle(context),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    name,
                    style: isCurrent
                        ? TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          )
                        : null,
                  ),
                ),
                if (hasLevels)
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 15,
                    color: theme.hintColor,
                  ),
              ],
            ),
          ),
        );

        if (expanded && hasLevels) {
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
                    child: Text(
                      'Reasoning',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.hintColor),
                    ),
                  ),
                  for (final option in session.thinkingLevels)
                    _menuItem(
                      selected: option == level,
                      onPressed: () => session.setThinkingLevel(option),
                      child: Text(option),
                    ),
                ],
              ),
            ),
          );
        }
      }
    }
    return widgets;
  }

  ButtonStyle _menuItemStyle(BuildContext context) {
    final theme = Theme.of(context);
    return MenuItemButton.styleFrom(
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      textStyle: theme.textTheme.bodySmall,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    );
  }

  /// Compact menu row with a fixed check slot so labels stay aligned.
  Widget _menuItem({
    required bool selected,
    required VoidCallback onPressed,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    return MenuItemButton(
      onPressed: onPressed,
      leadingIcon: Icon(
        Icons.check,
        size: 15,
        color: selected ? theme.colorScheme.primary : Colors.transparent,
      ),
      style: _menuItemStyle(context),
      child: child,
    );
  }
}


