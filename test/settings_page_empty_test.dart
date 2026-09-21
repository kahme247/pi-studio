import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_studio/settings/pi_settings.dart';
import 'package:pi_studio/settings/settings_page.dart';

/// A brand-new pi install has no settings.json at all, so every section has to
/// render from an entirely absent key set — a different set of branches from
/// the populated case in settings_page_test.dart, and the one most likely to
/// divide by an absent number or index an empty list.
///
/// Separate file because it needs its own single `pumpWidget`; see the scope
/// note in settings_page_test.dart.
void main() {
  testWidgets('renders every section from an empty store', (tester) async {
    final settings = PiSettings.inMemory();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: SettingsPage(
            settings: settings,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump();

    for (final section in SettingsSection.values) {
      await tester.tap(find.text(section.label).first);
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        tester.takeException(),
        isNull,
        reason: 'section ${section.label} threw on an empty store',
      );
    }
  });
}
