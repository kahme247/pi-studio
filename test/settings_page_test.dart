import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_studio/settings/pi_settings.dart';
import 'package:pi_studio/settings/settings_page.dart';

/// The settings page is long, control-dense and driven by whatever happens to
/// be in the user's settings.json, so rendering every section is the test that
/// earns its keep — it catches layout overflow and dropdown assertion failures
/// that only show up with real data.
///
/// Scope note: this file pumps the widget exactly once. Repeated `pumpWidget`
/// calls that replace the tree proved unstable in this environment — the
/// isolate is torn down mid-run and every remaining case reports "did not
/// complete" with no exception. Any new case must be added *within* the single
/// test below, or in a new file with its own single pump.
///
/// Uses [PiSettings.inMemory] because a widget test body runs in a fake-async
/// zone where real dart:io futures never complete. Disk round-trips are covered
/// by pi_settings_test.dart using plain `test()`.
void main() {
  testWidgets('renders every section and binds edits to the store',
      (tester) async {
    const models = <({String provider, String id, String label})>[
      (
        provider: 'cliproxyapi',
        id: 'opencode-go/muse-spark',
        label: 'Muse Spark',
      ),
      (provider: 'anthropic', id: 'claude-sonnet-4', label: 'Sonnet 4'),
    ];

    final settings = PiSettings.inMemory(
      data: {
        'defaultProvider': 'cliproxyapi',
        // Deliberately not one of the models above: a saved model is very often
        // absent from what the open session reported, and DropdownButton
        // asserts when its value has no matching item.
        'defaultModel': 'some-provider/not-listed',
        'defaultThinkingLevel': 'high',
        'hideThinkingBlock': false,
        'cacheWarming': 'idle',
        'defaultProjectTrust': 'always',
        'defaultTools': ['read', 'powershell'],
        'compaction': {'enabled': true, 'reserveTokens': 16384},
        'branchSummary': {'skipPrompt': true},
        'sessionDir': 'C:/sessions',
        'retry': {
          'enabled': true,
          'maxRetries': 3,
          'provider': {'maxRetries': 0},
        },
        'steeringMode': 'one-at-a-time',
        'transport': 'auto',
        'theme': 'dark/dark',
        'tuiMode': 'fullscreen',
        'markdown': {'mermaid': 'streaming'},
        'packages': ['npm:@juicesharp/rpiv-todo'],
        'skills': ['C:/Users/Khaled/plugins/some-skill'],
        'themes': ['C:/themes/x.json'],
        'httpProxy': 'http://127.0.0.1:7890',
        'enableAnalytics': false,
        // Unmodelled keys the page must not choke on, and must not clobber.
        'subagents': {
          'agentOverrides': {
            'worker': {'model': 'x/y'},
          },
        },
        'tokenSpeed': {'display': 'full'},
        'lastChangelogVersion': '0.86.1',
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: SettingsPage(
            settings: settings,
            onClose: () {},
            availableModels: models,
          ),
        ),
      ),
    );
    await tester.pump();

    // The unknown value still needs a dropdown entry, or it would assert.
    expect(find.text('some-provider/not-listed'), findsWidgets);

    for (final section in SettingsSection.values) {
      await tester.tap(find.text(section.label).first);
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        tester.takeException(),
        isNull,
        reason: 'section ${section.label} threw while building',
      );
      expect(find.text(section.label).first, findsOneWidget);
    }

    // About is last; come back to Agent for the edit checks.
    await tester.tap(find.text('Agent').first);
    await tester.pump(const Duration(milliseconds: 250));

    // A toggle binds straight through to the store.
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(settings.readBool('hideThinkingBlock'), isTrue);
    expect(settings.dirty, isTrue);

    // Typing commits per keystroke. Save is disabled while nothing is dirty and
    // a disabled button cannot take focus, so a blur-to-commit field would
    // deadlock the user.
    await tester.enterText(find.byType(TextField).first, 'anthropic');
    await tester.pump();
    expect(settings.readString('defaultProvider'), 'anthropic');
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
      isNotNull,
    );

    // Clearing removes the key, so pi falls back to its own default rather than
    // being pinned to an empty string.
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();
    expect(settings.readString('defaultProvider'), isNull);

    // Keys the page does not model survive all of the above untouched.
    expect(settings.read('tokenSpeed.display'), 'full');
    expect(settings.read('lastChangelogVersion'), '0.86.1');
  });
}
