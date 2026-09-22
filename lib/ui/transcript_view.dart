// Transcript widgets: chat items, activity blocks, scrubber, skeleton.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../state/session_controller.dart';
import 'app_theme.dart';
import 'primitives.dart';

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
      opacity: Tween<double>(
        begin: 0.2,
        end: 1,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
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
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
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

class ChatItemView extends StatefulWidget {
  const ChatItemView(this.item, {super.key, this.live = false});

  final ChatItem item;

  /// True for the assistant message that tokens are still arriving in.
  final bool live;

  @override
  State<ChatItemView> createState() => _ChatItemViewState();
}

class _ChatItemViewState extends State<ChatItemView> {
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
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
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ),
            ],
          ),
        );
      case ItemKind.assistant:
        return AssistantMessageView(item: item, live: widget.live);
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
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
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
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              if (args.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Arguments', style: theme.textTheme.labelSmall),
                ),
                const SizedBox(height: 4),
                CodeBox(args),
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
                CodeBox(result),
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
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
          ),
        );
    }
  }
}

class AssistantMessageView extends StatefulWidget {
  const AssistantMessageView({
    super.key,
    required this.item,
    this.live = false,
  });

  final ChatItem item;

  /// True while this message is the one still being written.
  final bool live;

  @override
  State<AssistantMessageView> createState() => _AssistantMessageViewState();
}

class _AssistantMessageViewState extends State<AssistantMessageView> {
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
              duration: motion(context, 100),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: widget.item.text));
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
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.hintColor,
                      ),
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

/// Vertical timeline scrubber matching the turn navigator from the reference.
/// Subtle tick marks on the left; active turn is wider and brighter.
/// Tap jumps to that turn; hover displays the prompt preview.
class TurnScrubber extends StatelessWidget {
  const TurnScrubber({
    super.key,
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
    final snippet = widget.turn.item.text
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final preview = snippet.length <= 60
        ? snippet
        : '${snippet.substring(0, 60)}…';
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
            padding: const EdgeInsets.symmetric(vertical: 3.5, horizontal: 2),
            child: AnimatedContainer(
              duration: motion(context, 120),
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

/// One agent turn: a "Processing 2m 20s · 76 token/s" header, one-line steps,
/// and a pulsing status line while running. Collapses to a summary otherwise.
class ActivityBlockView extends StatefulWidget {
  const ActivityBlockView({
    super.key,
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
  State<ActivityBlockView> createState() => _ActivityBlockViewState();
}

class _ActivityBlockViewState extends State<ActivityBlockView> {
  var _expanded = false;

  bool get _hasError => widget.items.any((item) => item.isError);

  @override
  void didUpdateWidget(ActivityBlockView oldWidget) {
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
                    color: _hasError
                        ? theme.colorScheme.error
                        : theme.hintColor,
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
              duration: motion(context, 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in steps)
                    _Appear(item: item, offset: 4, child: _StepRow(item)),
                ],
              ),
            )
          else if (running && steps.isNotEmpty)
            _Appear(item: steps.last, offset: 4, child: _StepRow(steps.last)),
          if (running) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const _PulseBars(),
                const SizedBox(width: 8),
                Text(
                  '$_statusLabel…',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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
                  color: item.isError
                      ? theme.colorScheme.error
                      : theme.hintColor,
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
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  )
                : CodeBox(detail),
          ),
      ],
    );
  }
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
                    // Working, not branding: same green the reference uses for
                    // a live session.
                    color: liveGreen,
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

/// Skeleton placeholder shaped like a transcript, shown while a session loads.
/// Skeletons beat spinners: the layout doesn't jump when content arrives.
class TranscriptSkeleton extends StatefulWidget {
  const TranscriptSkeleton({super.key});

  @override
  State<TranscriptSkeleton> createState() => _TranscriptSkeletonState();
}

class _TranscriptSkeletonState extends State<TranscriptSkeleton>
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
          : Tween<double>(
              begin: 0.5,
              end: 1,
            ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
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
    listBullet: TextStyle(fontSize: 14.5, height: 1.5, color: theme.hintColor),
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
