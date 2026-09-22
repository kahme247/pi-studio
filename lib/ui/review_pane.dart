// Review rail widgets: diff view, file tree, terminal panel.
import 'dart:io';

import 'package:flutter/material.dart';

import '../git/git_ops.dart';
import 'app_theme.dart';
import 'primitives.dart';
import 'transcript_view.dart';

/// Review tab: changed files with per-file counts and a line-numbered diff,
/// shaped like the reference review pane.
class DiffView extends StatefulWidget {
  const DiffView({required this.workingDirectory, super.key});

  final String workingDirectory;

  @override
  State<DiffView> createState() => _DiffViewState();
}

class _DiffViewState extends State<DiffView> {
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
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                '+${formatCount(additions)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: diffAdded,
                  fontFamily: 'GeistMono',
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '-${formatCount(deletions)}',
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
              ? const TranscriptSkeleton()
              : _files.isEmpty
              ? Center(
                  child: Text(
                    'No changes.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
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
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'GeistMono',
                    ),
                  ),
                ),
                Text(
                  '+${formatCount(selected.additions)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: diffAdded,
                    fontFamily: 'GeistMono',
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '-${formatCount(selected.deletions)}',
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
    final green = diffAdded;
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
    final green = diffAdded;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: _files.length,
      itemBuilder: (context, index) {
        final file = _files[index];
        final name = file.path.split('/').last;
        final separator = file.path.lastIndexOf('/');
        final dir = separator > 0 ? file.path.substring(0, separator) : '';
        final selected = file.path == _selected;
        final statusColor = switch (file.status) {
          'A' || '??' => green,
          'D' => theme.colorScheme.error,
          '?' => theme.hintColor,
          _ => theme.colorScheme.primary,
        };
        return HoverTint(
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
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.hintColor,
                          ),
                        ),
                    ],
                  ),
                ),
                if (file.additions > 0)
                  Text(
                    '+${file.additions}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: green,
                      fontFamily: 'GeistMono',
                    ),
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
class FileTree extends StatefulWidget {
  const FileTree({super.key, required this.root});

  final String root;

  @override
  State<FileTree> createState() => _FileTreeState();
}

class _FileTreeState extends State<FileTree> {
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

  void _openFile(String path) =>
      Process.start(Platform.isWindows ? 'explorer' : 'xdg-open', [path]);

  List<Widget> _rows(String path, int depth) {
    final theme = Theme.of(context);
    final widgets = <Widget>[];
    for (final entry in _cache[path] ?? const <FileSystemEntity>[]) {
      final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final isDir = entry is Directory;
      final expanded = _expanded.contains(entry.path);
      widgets.add(
        HoverTint(
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
class TerminalPanel extends StatefulWidget {
  const TerminalPanel({super.key, required this.workingDirectory});

  final String workingDirectory;

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
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
        _entries[_entries.length - 1] = (
          command: command,
          output: '$error',
          code: -1,
        );
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
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
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
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontFamily: 'GeistMono',
                              ),
                            ),
                          ),
                          if (entry.code != 0)
                            Text(
                              'exit ${entry.code}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                        ],
                      ),
                      if (entry.output.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, bottom: 10),
                          child: CodeBox(entry.output.trim()),
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
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'GeistMono',
                  ),
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
