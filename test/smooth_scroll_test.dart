import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_studio/ui/smooth_scroll.dart';

/// Wheel input is the one input path this app overrides, and the accumulation
/// rule is easy to get subtly wrong: restart the ease on every event and a fast
/// spin under-shoots, because each event re-targets from a mid-flight offset.
///
/// Scope note: this file deliberately holds a single `testWidgets`. Rendering
/// app widgets across several tests — or several scenarios in one test — proved
/// unstable in this environment: the isolate is torn down mid-run and every
/// remaining case reports "did not complete" with no exception. Add cases only
/// after confirming a run of `flutter test test/smooth_scroll_test.dart` stays
/// green a dozen times over.
void main() {
  /// Bounded settle. `pumpAndSettle` waits up to ten minutes for an animation
  /// that may never end, which turns a stuck ease into a hung test run.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('wheel input eases, and a fast spin accumulates',
      (tester) async {
    final controller = SmoothScrollController(
      wheelDuration: () => const Duration(milliseconds: 160),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: controller,
          itemCount: 200,
          itemBuilder: (context, index) =>
              SizedBox(height: 50, child: Text('row $index')),
        ),
      ),
    );

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    final centre = tester.getCenter(find.byType(ListView));
    await tester.sendEventToBinding(pointer.hover(centre));

    // One notch eases toward the target rather than landing on it instantly.
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 300)));
    await tester.pump();
    // The ease begins at t=0, so nothing has moved — and critically the full
    // 300 has not been applied either.
    expect(controller.offset, 0);
    await tester.pump(const Duration(milliseconds: 40));
    expect(controller.offset, greaterThan(0));
    expect(controller.offset, lessThan(300));
    await settle(tester);
    expect(controller.offset, closeTo(300, 1));

    // A second notch mid-ease adds to the destination. Landing near 300 would
    // mean it re-targeted from the mid-flight offset and dropped the remainder.
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 200)));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 200)));
    await settle(tester);
    expect(controller.offset, closeTo(700, 2));

    await tester.sendEventToBinding(pointer.removePointer());
  });
}
