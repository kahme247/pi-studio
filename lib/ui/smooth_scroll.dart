import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A [ScrollController] that eases wheel input instead of applying it
/// instantly, which is what Flutter does by default.
///
/// A mouse wheel reports one large delta per notch. Applying that instantly
/// makes the content lurch rather than scroll, and on a long transcript it
/// reads as the text jumping between positions. This animates each notch
/// instead, and accumulates the destination while an ease is still running so
/// a fast spin travels the whole distance rather than restarting a short
/// animation on every event.
class SmoothScrollController extends ScrollController {
  SmoothScrollController({
    required this.wheelDuration,
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
  });

  /// Read at event time, so a caller can switch easing off for reduced motion
  /// without the controller — and therefore its positions — being recreated.
  ///
  /// Returning [Duration.zero] restores Flutter's instant behaviour.
  final Duration Function() wheelDuration;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _SmoothScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
      wheelDuration: wheelDuration,
    );
  }
}

class _SmoothScrollPosition extends ScrollPositionWithSingleContext {
  _SmoothScrollPosition({
    required super.physics,
    required super.context,
    required this.wheelDuration,
    super.oldPosition,
  });

  final Duration Function() wheelDuration;

  /// Destination while an ease is in flight.
  double? _pending;

  @override
  void pointerScroll(double delta) {
    final duration = wheelDuration();
    if (delta == 0.0 ||
        duration == Duration.zero ||
        !hasPixels ||
        !hasContentDimensions) {
      super.pointerScroll(delta);
      return;
    }
    final from = _pending ?? pixels;
    final target = (from + delta).clamp(minScrollExtent, maxScrollExtent);
    _pending = target;
    updateUserScrollDirection(
      delta > 0 ? ScrollDirection.reverse : ScrollDirection.forward,
    );
    animateTo(target, duration: duration, curve: Curves.easeOutCubic)
        .whenComplete(() {
      // Only clear when nothing newer arrived while this ease was running.
      if (_pending == target) _pending = null;
    });
  }
}
