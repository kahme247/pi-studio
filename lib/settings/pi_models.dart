import 'dart:io';

import '../pi/session_store.dart';
import 'json_file_store.dart';

/// The API types `models.json` accepts, from pi's models.md.
///
/// Extensions can register more (`mistral-conversations`, `bedrock-converse-stream`,
/// `azure-openai-responses`), but those are only reachable from an extension,
/// so offering them here would produce a file pi silently ignores.
const piModelApis = <String>[
  'openai-completions',
  'openai-responses',
  'anthropic-messages',
  'google-generative-ai',
];

/// pi's custom-provider file, `~/.pi/agent/models.json`.
///
/// This is the documented, file-based surface for adding providers and models,
/// and pi re-reads it every time the model picker opens — so edits here take
/// effect without restarting a session.
///
/// Providers registered by extensions are deliberately out of reach: they live
/// inside third-party npm packages with their own schemas. What this file can
/// do is add new providers, and override built-in ones by reusing their id.
class PiModels extends JsonFileStore {
  PiModels({String? filePath}) : super(path: filePath ?? defaultPath);

  PiModels.inMemory({super.data}) : super.inMemory();

  static String get defaultPath =>
      '${piAgentDir().path}${Platform.pathSeparator}models.json';

  // ------------------------------------------------------------- providers

  Map<String, dynamic> get _providers {
    final existing = read('providers');
    return existing is Map<String, dynamic> ? existing : <String, dynamic>{};
  }

  List<String> get providerIds => _providers.keys.toList()..sort();

  Map<String, dynamic>? provider(String id) {
    final value = _providers[id];
    return value is Map<String, dynamic> ? value : null;
  }

  void putProvider(String id, Map<String, dynamic> value) {
    mutate((data) {
      final existing = data['providers'];
      final Map<String, dynamic> providers;
      if (existing is Map<String, dynamic>) {
        providers = existing;
      } else {
        providers = <String, dynamic>{};
        data['providers'] = providers;
      }
      providers[id] = value;
    });
  }

  void renameProvider(String from, String to) {
    if (from == to) return;
    mutate((data) {
      final existing = data['providers'];
      if (existing is! Map<String, dynamic>) return;
      final value = existing.remove(from);
      if (value != null) existing[to] = value;
    });
  }

  /// Removes a provider. The empty `providers` map is left in place, which is
  /// how pi writes its own file when nothing is configured.
  void removeProvider(String id) {
    mutate((data) {
      final existing = data['providers'];
      if (existing is Map<String, dynamic>) existing.remove(id);
    });
  }

  /// Sets or clears a scalar field on a provider. A null or blank value removes
  /// the key, so pi's own default applies instead of an empty string.
  void setProviderField(String id, String key, Object? value) {
    mutate((data) {
      final existing = data['providers'];
      if (existing is! Map<String, dynamic>) return;
      final provider = existing[id];
      if (provider is! Map<String, dynamic>) return;
      if (value == null || (value is String && value.trim().isEmpty)) {
        provider.remove(key);
      } else {
        provider[key] = value;
      }
    });
  }

  // ---------------------------------------------------------------- models

  /// The raw `models` array for a provider, or an empty list.
  ///
  /// The entries are live maps from the underlying document, so callers must
  /// not mutate them directly — use the helpers below.
  List<Object?> modelsOf(String id) {
    final models = provider(id)?['models'];
    return models is List ? models : const [];
  }

  /// Applies [change] to a provider's `models` array, creating it if needed.
  void _withModels(String providerId, void Function(List<Object?> models) change) {
    mutate((data) {
      final providers = data['providers'];
      if (providers is! Map<String, dynamic>) return;
      final provider = providers[providerId];
      if (provider is! Map<String, dynamic>) return;

      final existing = provider['models'];
      // Copy into a plain List<Object?> rather than mutating the decoded list
      // in place: a hand-written list literal can carry a narrower runtime type
      // (List<Map<String, String>>) that rejects the maps added below.
      final models = <Object?>[if (existing is List) ...existing];

      change(models);

      // An empty array is not the same as an absent key: pi reads a present
      // `models` as "these are the provider's models". Drop the key once the
      // last model goes, so a built-in provider's own list is left alone.
      if (models.isEmpty) {
        provider.remove('models');
      } else {
        provider['models'] = models;
      }
    });
  }

  void setModelField(String providerId, int index, String key, Object? value) {
    _withModels(providerId, (models) {
      if (index < 0 || index >= models.length) return;
      final model = models[index];
      if (model is! Map<String, dynamic>) return;
      if (value == null || (value is String && value.trim().isEmpty)) {
        model.remove(key);
      } else {
        model[key] = value;
      }
    });
  }

  void addModel(String providerId) {
    _withModels(providerId, (models) => models.add(<String, dynamic>{}));
  }

  void removeModelAt(String providerId, int index) {
    _withModels(providerId, (models) {
      if (index >= 0 && index < models.length) models.removeAt(index);
    });
  }

  /// Adds any [ids] not already present, in order. Used by model discovery.
  int addMissingModels(String providerId, Iterable<String> ids) {
    var added = 0;
    _withModels(providerId, (models) {
      final present = <String>{
        for (final model in models)
          if (model is Map && model['id'] is String) model['id'] as String,
      };
      for (final id in ids) {
        if (id.trim().isEmpty || !present.add(id)) continue;
        models.add(<String, dynamic>{'id': id});
        added++;
      }
    });
    return added;
  }

  // ------------------------------------------------------------ validation

  /// Problems that would make pi ignore this provider, or mis-handle it.
  ///
  /// Shown as a warning rather than blocking the save: the user may be midway
  /// through a change, and the file is backed up on every write anyway.
  List<String> validate(String id, Map<String, dynamic>? provider) {
    final problems = <String>[];
    if (provider == null) return problems;

    final baseUrl = provider['baseUrl'];
    if (baseUrl is! String || baseUrl.trim().isEmpty) {
      problems.add('No base URL, so pi cannot reach this provider.');
    } else if (!baseUrl.startsWith('http://') &&
        !baseUrl.startsWith('https://')) {
      problems.add('Base URL should start with http:// or https://.');
    }

    final models = provider['models'];
    final hasModels = models is List && models.isNotEmpty;
    final api = provider['api'];
    if (hasModels && (api is! String || !piModelApis.contains(api))) {
      problems.add(
        'This provider defines models but no API type, so pi will skip it. '
        'Pick one of: ${piModelApis.join(', ')}.',
      );
    } else if (api is String && api.isNotEmpty && !piModelApis.contains(api)) {
      problems.add('"$api" is not an API type models.json understands.');
    }

    if (models is List) {
      final seen = <String>{};
      for (final model in models) {
        if (model is! Map) continue;
        final modelId = model['id'];
        if (modelId is! String || modelId.trim().isEmpty) {
          problems.add('A model needs an id — pi identifies models by it.');
          continue;
        }
        if (!seen.add(modelId)) {
          problems.add('Two models share the id "$modelId"; only one is used.');
        }
      }
    }
    return problems;
  }

  /// Ids that appear more than once, so the UI can flag the offending row.
  Set<String> duplicatedModelIds(String providerId) {
    final seen = <String>{};
    final dupes = <String>{};
    for (final model in modelsOf(providerId)) {
      if (model is! Map) continue;
      final id = model['id'];
      if (id is! String || id.trim().isEmpty) continue;
      if (!seen.add(id)) dupes.add(id);
    }
    return dupes;
  }
}
