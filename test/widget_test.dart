import 'package:flutter_test/flutter_test.dart';

import 'package:pi_studio/main.dart';

void main() {
  testWidgets('startup shows the studio shell with no sessions', (
    tester,
  ) async {
    await tester.pumpWidget(const PiStudioApp());

    expect(find.text('Pi Studio'), findsWidgets);
    expect(find.text('What do you want to build?'), findsOneWidget);
    expect(find.text('New task'), findsWidgets);
    expect(find.text('Add project'), findsWidgets);
  });
}
