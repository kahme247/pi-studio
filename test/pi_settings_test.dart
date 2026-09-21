import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_studio/settings/pi_settings.dart';

/// The settings page rewrites a file the user depends on, so the important
/// guarantee is that keys this UI does not model come back out intact.
void main() {
  late Directory dir;
  late File file;
  late PiSettings settings;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pi_settings_test');
    file = File('${dir.path}${Platform.pathSeparator}settings.json');
    settings = PiSettings(filePath: file.path);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<Map<String, dynamic>> writeAndRead(
    Map<String, dynamic> initial,
    void Function(PiSettings settings) mutate,
  ) async {
    await file.writeAsString(jsonEncode(initial));
    await settings.load();
    mutate(settings);
    await settings.save();
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  test('preserves keys the UI does not model', () async {
    final original = {
      'defaultModel': 'old-model',
      'subagents': {
        'agentOverrides': {
          'worker': {'model': 'some-provider/worker-model'},
        },
      },
      'tokenSpeed': {'display': 'full', 'useProviderTokens': true},
      'packages': ['npm:@juicesharp/rpiv-todo'],
      'lastChangelogVersion': '0.86.1',
    };

    final result = await writeAndRead(
      original,
      (s) => s.write('defaultModel', 'new-model'),
    );

    expect(result['defaultModel'], 'new-model');
    // The whole point: unmodelled subtrees survive byte-for-byte in meaning.
    expect(result['subagents'], original['subagents']);
    expect(result['tokenSpeed'], original['tokenSpeed']);
    expect(result['packages'], original['packages']);
    expect(result['lastChangelogVersion'], '0.86.1');
  });

  test('nested writes create only the maps they need', () async {
    final result = await writeAndRead(
      {'theme': 'dark/dark'},
      (s) => s.write('compaction.enabled', false),
    );

    expect(result['compaction'], {'enabled': false});
    expect(result['theme'], 'dark/dark');
  });

  test('writing null removes the key and prunes emptied parents', () async {
    final result = await writeAndRead(
      {
        'compaction': {'enabled': true, 'reserveTokens': 16384},
        'theme': 'dark',
      },
      (s) => s.write('compaction.reserveTokens', null),
    );

    expect(result['compaction'], {'enabled': true});

    final pruned = await writeAndRead(
      {
        'compaction': {'enabled': true},
        'theme': 'dark',
      },
      (s) => s.write('compaction.enabled', null),
    );
    expect(pruned.containsKey('compaction'), isFalse);
    expect(pruned['theme'], 'dark');
  });

  test('an empty list removes the key rather than writing []', () async {
    final result = await writeAndRead(
      {
        'defaultTools': ['read', 'bash'],
        'theme': 'dark',
      },
      (s) => s.writeList('defaultTools', const []),
    );

    expect(result.containsKey('defaultTools'), isFalse);
    expect(result['theme'], 'dark');
  });

  test('writeList trims and drops blank entries', () async {
    final result = await writeAndRead(
      <String, dynamic>{},
      (s) => s.writeList('skills', ['  C:/a/b  ', '', '   ', 'C:/c']),
    );

    expect(result['skills'], ['C:/a/b', 'C:/c']);
  });

  test('reads fall back when a key holds the wrong type', () async {
    await file.writeAsString(jsonEncode({'compaction': 'not-an-object'}));
    await settings.load();

    expect(settings.read('compaction.enabled'), isNull);
    expect(settings.readBool('compaction.enabled', fallback: true), isTrue);
    expect(settings.readList('compaction'), isEmpty);
    expect(settings.readNumber('missing.deep'), isNull);
  });

  test('a corrupt file reports an error instead of throwing', () async {
    await file.writeAsString('{ this is not json');
    await settings.load();

    expect(settings.error, isNotNull);
    expect(settings.keys, isEmpty);
  });

  test('save keeps a .bak of the previous revision', () async {
    final original = {'theme': 'dark'};
    final result = await writeAndRead(
      original,
      (s) => s.write('theme', 'light'),
    );

    expect(result['theme'], 'light');
    final backup = File('${file.path}.bak');
    expect(await backup.exists(), isTrue);
    expect(jsonDecode(await backup.readAsString()), original);
  });

  test('discard drops unsaved edits', () async {
    await file.writeAsString(jsonEncode({'theme': 'dark'}));
    await settings.load();

    settings.write('theme', 'light');
    expect(settings.dirty, isTrue);

    await settings.discard();
    expect(settings.dirty, isFalse);
    expect(settings.readString('theme'), 'dark');
  });

  test('normalises Windows backslashes for JSON paths', () {
    expect(normalizeSettingsPath(r'C:\Users\me\skills'), 'C:/Users/me/skills');
    expect(normalizeSettingsPath('  ~/.pi/agent  '), '~/.pi/agent');
  });
}
