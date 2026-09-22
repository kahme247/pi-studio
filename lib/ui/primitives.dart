// Shared leaf widgets: hover feedback, motion, code, splitters, rail tabs.
import 'dart:async';

import 'package:flutter/material.dart';

/// Animation duration that collapses to zero when the OS asks for reduced
/// motion.
Duration motion(BuildContext context, [int ms = 140]) =>
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
class HoverTint extends StatefulWidget {
  const HoverTint({
    super.key,
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
  State<HoverTint> createState() => _HoverTintState();
}

class _HoverTintState extends State<HoverTint> {
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
          duration: motion(context, 110),
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

/// Rail tab: the active tab holds a primary tint, inactive tabs ease toward it
/// on hover so the tab strip responds under the pointer.
class RailTabButton extends StatefulWidget {
  const RailTabButton({
    super.key,
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
  State<RailTabButton> createState() => _RailTabButtonState();
}

class _RailTabButtonState extends State<RailTabButton> {
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
    final duration = motion(context, 120);

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
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
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

/// Tabs of the right-hand panel.
enum RailTab { review, files, terminal }

/// Fade-in with an optional stagger delay, used for list reveals.
/// Plays once per element and collapses under reduced motion.
class FadeIn extends StatefulWidget {
  const FadeIn({super.key, required this.child, this.delay = Duration.zero});

  final Widget child;
  final Duration delay;

  @override
  State<FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<FadeIn> with SingleTickerProviderStateMixin {
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

/// Draggable pane splitter: 8px hit area, hover highlight, double-click reset.
class SplitHandle extends StatefulWidget {
  const SplitHandle({super.key, required this.onDrag, required this.onReset, this.color});

  final ValueChanged<double> onDrag;
  final VoidCallback onReset;
  final Color? color;

  @override
  State<SplitHandle> createState() => _SplitHandleState();
}

class _SplitHandleState extends State<SplitHandle> {
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
          duration: motion(context, 90),
          width: 8,
          color: _hovered
              ? theme.colorScheme.primary.withValues(alpha: 0.35)
              : (widget.color ?? Colors.transparent),
        ),
      ),
    );
  }
}

class CodeBox extends StatelessWidget {
  const CodeBox(this.text, {super.key});

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

String formatCount(Object? value) {
  if (value is! num) return '–';
  final digits = value.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
