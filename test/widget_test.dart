import 'package:flutter_test/flutter_test.dart';

import 'package:pi_studio/main.dart';

void main() {
  testWidgets('startup shows the studio shell with no sessions', (
    tester,
  ) async {
    await tester.pumpWidget(const PiStudioApp());

    expect(find.text('Pi Studio'), findsOneWidget);
    expect(find.text('No session selected.'), findsOneWidget);
    expect(find.text('Add project'), findsWidgets);
  });
}
