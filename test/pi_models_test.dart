import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_studio/settings/pi_models.dart';

/// models.json is the file pi reads to learn about custom providers, and it is
/// hand-editable. The same guarantee as settings.json applies: keys this UI
/// does not model must survive a save, or editing a provider in the app would
/// quietly throw away `compat`, `modelOverrides`, and anything a future pi adds.
void main() {
  late Directory dir;
  late File file;
  late PiModels models;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('pi_models_test');
    file = File('${dir.path}${Platform.pathSeparator}models.json');
    models = PiModels(filePath: file.path);
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<Map<String, dynamic>> writeAndRead(
    Map<String, dynamic> initial,
    void Function(PiModels store) mutate,
  ) async {
    await file.writeAsString(jsonEncode(initial));
    await models.load();
    mutate(models);
    await models.save();
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  test('preserves provider fields the UI does not model', () async {
    final original = <String, dynamic>{
      'providers': {
        'openrouter': {
          'baseUrl': 'https://openrouter.ai/api/v1',
          'modelOverrides': {
            'anthropic/claude-sonnet-4': {
              'contextWindow': 200000,
            },
          },
          'compat': {'supportsStore': false},
          'oauth': {'type': 'radius'},
        },
      },
      'somethingNew': {'from': 'a future pi'},
    };

    final result = await writeAndRead(
      original,
      (store) => store.setProviderField('openrouter', 'api', 'openai-completions'),
    );

    final provider = (result['providers'] as Map)['openrouter'] as Map;
    expect(provider['api'], 'openai-completions');
    expect(provider['modelOverrides'], original['providers']!['openrouter']!['modelOverrides']);
    expect(provider['compat'], {'supportsStore': false});
    expect(provider['oauth'], {'type': 'radius'});
    expect(result['somethingNew'], {'from': 'a future pi'});
  });

  test('setting a field blank removes it rather than writing an empty string',
      () async {
    final result = await writeAndRead(
      {
        'providers': {
          'x': {'baseUrl': 'http://a', 'api': 'openai-completions'},
        },
      },
      (store) => store.setProviderField('x', 'api', '   '),
    );

    expect((result['providers'] as Map)['x'], {'baseUrl': 'http://a'});
  });

  test('addMissingModels skips ids already present', () {
    final store = PiModels.inMemory(
      data: {
        'providers': {
          'x': {
            'models': [
              {'id': 'a'},
              {'id': 'b'},
            ],
          },
        },
      },
    );

    final added = store.addMissingModels('x', ['b', 'c', 'a', 'd', '  ']);

    expect(added, 2);
    final ids = store
        .modelsOf('x')
        .whereType<Map>()
        .map((m) => m['id'])
        .toList();
    expect(ids, ['a', 'b', 'c', 'd']);
  });

  test('removing the last model drops the models key entirely', () {
    // A present-but-empty `models` array tells pi "this provider has no
    // models", which would hide a built-in provider's own list. An absent key
    // means "leave it alone".
    final store = PiModels.inMemory(
      data: {
        'providers': {
          'anthropic': {
            'baseUrl': 'https://proxy.example.com',
            'models': [
              {'id': 'only-one'},
            ],
          },
        },
      },
    );

    store.removeModelAt('anthropic', 0);

    expect(store.provider('anthropic')!.containsKey('models'), isFalse);
    expect(store.provider('anthropic')!['baseUrl'], 'https://proxy.example.com');
  });

  test('removing a provider leaves the empty providers map pi writes', () {
    final store = PiModels.inMemory(
      data: {
        'providers': {
          'x': {'baseUrl': 'http://a'},
        },
      },
    );

    store.removeProvider('x');

    expect(store.providerIds, isEmpty);
    expect(store.keys, ['providers']);
  });

  test('renameProvider moves the value and keeps the rest', () {
    final store = PiModels.inMemory(
      data: {
        'providers': {
          'old': {'baseUrl': 'http://a'},
          'other': {'baseUrl': 'http://b'},
        },
      },
    );

    store.renameProvider('old', 'new');

    expect(store.providerIds, ['new', 'other']);
    expect(store.provider('new')!['baseUrl'], 'http://a');
  });

  test('addModel on a provider that does not exist is a no-op', () {
    final store = PiModels.inMemory(data: {'providers': <String, dynamic>{}});
    store.addModel('ghost');
    expect(store.providerIds, isEmpty);
  });

  group('validate', () {
    test('flags a missing or non-http base URL', () {
      final store = PiModels.inMemory();
      expect(
        store.validate('x', {'api': 'openai-completions'}),
        contains(contains('No base URL')),
      );
      expect(
        store.validate('x', {'baseUrl': 'localhost:1234'}),
        contains(contains('http://')),
      );
    });

    test('flags models defined without an API type', () {
      final store = PiModels.inMemory();
      final problems = store.validate('x', {
        'baseUrl': 'http://localhost:1234/v1',
        'models': [
          {'id': 'a'},
        ],
      });
      expect(problems.join(' '), contains('no API type'));
    });

    test('flags an unknown API type', () {
      final store = PiModels.inMemory();
      final problems = store.validate('x', {
        'baseUrl': 'http://localhost:1234/v1',
        'api': 'openai',
      });
      expect(problems.join(' '), contains('not an API type'));
    });

    test('flags models without an id, and duplicate ids', () {
      final store = PiModels.inMemory();
      final problems = store.validate('x', {
        'baseUrl': 'http://localhost:1234/v1',
        'api': 'openai-completions',
        'models': [
          {'id': 'a'},
          {'id': 'a'},
          {'name': 'no id'},
        ],
      });
      expect(problems.join(' '), contains('needs an id'));
      expect(problems.join(' '), contains('share the id "a"'));
    });

    test('a bare reroute of a built-in provider is valid', () {
      final store = PiModels.inMemory();
      expect(
        store.validate('anthropic', {'baseUrl': 'https://proxy.example.com'}),
        isEmpty,
      );
    });
  });

  test('duplicatedModelIds points at just the offending ids', () {
    final store = PiModels.inMemory(
      data: {
        'providers': {
          'x': {
            'models': [
              {'id': 'a'},
              {'id': 'b'},
              {'id': 'a'},
              {'id': 'c'},
            ],
          },
        },
      },
    );

    expect(store.duplicatedModelIds('x'), {'a'});
  });

  test('a corrupt file reports an error instead of throwing', () async {
    await file.writeAsString('{ not json');
    await models.load();

    expect(models.error, isNotNull);
    expect(models.providerIds, isEmpty);
  });

  test('save keeps a .bak of the previous revision', () async {
    final original = {
      'providers': {
        'x': {'baseUrl': 'http://a'},
      },
    };
    await writeAndRead(original, (store) => store.addModel('x'));

    final backup = File('${file.path}.bak');
    expect(await backup.exists(), isTrue);
    expect(jsonDecode(await backup.readAsString()), original);
  });
}
