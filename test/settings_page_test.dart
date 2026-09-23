import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pi_studio/settings/pi_models.dart';
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
  testWidgets('renders every section and binds edits to the store', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1200);
    tester.view.devicePixelRatio = 1;
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

    final modelsConfig = PiModels.inMemory(
      data: {
        'providers': {
          // A local OpenAI-compatible server: the common case.
          'local-llm': {
            'baseUrl': 'http://localhost:11434/v1',
            'api': 'openai-completions',
            'apiKey': r'$LOCAL_LLM_KEY',
            'headers': {'x-tenant': 'acme'},
            'models': [
              {
                'id': 'llama3.1:8b',
                'name': 'Llama 3.1 8B',
                'reasoning': false,
                'input': ['text'],
                'contextWindow': 128000,
                'maxTokens': 32000,
                'cost': {'input': 0.5, 'output': 1.5},
              },
              // Deliberately incomplete: no id, which validation must catch.
              {'name': 'half-typed'},
            ],
          },
          // Rerouting a built-in provider: no models array on purpose.
          'anthropic': {'baseUrl': 'https://proxy.example.com'},
        },
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: SettingsPage(
            settings: settings,
            models: modelsConfig,
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
      if (section == SettingsSection.providers) {
        expect(find.text('API key'), findsNothing);
        await tester.tap(find.text('local-llm'));
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('API key'), findsOneWidget);
        tester.widget<Switch>(find.byType(Switch).first).onChanged!(true);
        await tester.pump();
        expect(modelsConfig.provider('local-llm')?['authHeader'], isTrue);
        expect(modelsConfig.dirty, isFalse);
      }
    }

    // About is last; come back to Agent for the edit checks.
    await tester.tap(find.text('Agent').first);
    await tester.pump(const Duration(milliseconds: 250));

    // A toggle persists immediately instead of waiting for the page Save.
    tester.widget<Switch>(find.byType(Switch).first).onChanged!(true);
    await tester.pump();
    expect(settings.readBool('hideThinkingBlock'), isTrue);
    expect(settings.dirty, isFalse);

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
