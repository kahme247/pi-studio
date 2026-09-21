import 'dart:convert';
import 'dart:io';

/// The result of expanding a `models.json` value the way pi resolves it.
class ConfigValue {
  const ConfigValue.resolved(String this.value) : reason = null;
  const ConfigValue.unresolved(String this.reason) : value = null;

  final String? value;
  final String? reason;

  bool get ok => value != null;
}

final _envName = RegExp(r'[A-Za-z_][A-Za-z0-9_]*');

/// Expands the value syntax `models.json` uses for `apiKey` and `headers`.
///
/// Mirrors pi: `$$` is a literal `$`, `$!` a literal `!`, `$NAME` and
/// `${NAME}` interpolate the environment, and a missing variable leaves the
/// value unresolved.
///
/// The one deliberate difference is `!command`. Pi runs it through a shell at
/// request time; a settings page has no business executing commands found in a
/// config file just to populate a dropdown, so this reports it as unresolved
/// and the caller explains why.
ConfigValue expandConfigValue(String raw, Map<String, String> env) {
  if (raw.startsWith('!')) {
    return const ConfigValue.unresolved(
      'this value runs a shell command, which this page will not execute. '
      'Fill the list in by hand, or leave it to pi at request time.',
    );
  }

  final out = StringBuffer();
  var i = 0;
  while (i < raw.length) {
    final ch = raw[i];
    if (ch != r'$') {
      out.write(ch);
      i++;
      continue;
    }
    if (i + 1 >= raw.length) {
      out.write(r'$');
      break;
    }
    final next = raw[i + 1];
    if (next == r'$') {
      out.write(r'$');
      i += 2;
      continue;
    }
    if (next == '!') {
      out.write('!');
      i += 2;
      continue;
    }
    if (next == '{') {
      final close = raw.indexOf('}', i + 2);
      if (close == -1) {
        out.write(ch);
        i++;
        continue;
      }
      final name = raw.substring(i + 2, close);
      final value = env[name];
      if (value == null) {
        return ConfigValue.unresolved('environment variable $name is not set.');
      }
      out.write(value);
      i = close + 1;
      continue;
    }
    final match = _envName.matchAsPrefix(raw, i + 1);
    if (match == null) {
      out.write(r'$');
      i++;
      continue;
    }
    final name = match.group(0)!;
    final value = env[name];
    if (value == null) {
      return ConfigValue.unresolved('environment variable $name is not set.');
    }
    out.write(value);
    i = match.end;
  }
  return ConfigValue.resolved(out.toString());
}

/// Pulls model ids out of whatever a `/models` endpoint returned.
///
/// OpenAI-compatible servers answer `{"data": [{"id": ...}]}`; Anthropic uses
/// `{"data": [...]}` too, Google uses `{"models": [{"name": ...}]}`, and some
/// proxies just return a bare array. All of them are accepted, because
/// guessing wrong would mean a button that silently finds nothing.
List<String> parseModelIds(String body) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return const [];
  }

  List<Object?>? list;
  if (decoded is List) {
    list = decoded;
  } else if (decoded is Map) {
    for (final key in const ['data', 'models', 'model_ids']) {
      final candidate = decoded[key];
      if (candidate is List) {
        list = candidate;
        break;
      }
    }
  }
  if (list == null) return const [];

  final ids = <String>{};
  for (final entry in list) {
    if (entry is String) {
      if (entry.trim().isNotEmpty) ids.add(entry.trim());
      continue;
    }
    if (entry is Map) {
      final id = entry['id'] ?? entry['name'] ?? entry['model'];
      if (id is String && id.trim().isNotEmpty) {
        // Google returns "models/gemini-2.5-pro"; the id pi wants is the tail.
        ids.add(id.trim().split('/').last);
      }
    }
  }
  return ids.toList()..sort();
}

/// Where to ask a given API type for its model list.
Uri discoveryUri(String baseUrl, String api) {
  final base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
  if (api == 'anthropic-messages') {
    return Uri.parse(
      base.endsWith('/v1') ? '$base/models' : '$base/v1/models',
    );
  }
  return Uri.parse('$base/models');
}

/// Headers a discovery request needs for the given API type.
Map<String, String> discoveryHeaders({
  required String api,
  required String? apiKey,
  Map<String, String> extra = const {},
}) {
  final headers = <String, String>{'accept': 'application/json'};
  if (apiKey != null && apiKey.isNotEmpty) {
    if (api == 'anthropic-messages') {
      headers['x-api-key'] = apiKey;
      headers['anthropic-version'] = '2023-06-01';
    } else if (api == 'google-generative-ai') {
      // Google takes the key as a query parameter; handled by the caller.
    } else {
      headers['authorization'] = 'Bearer $apiKey';
    }
  }
  headers.addAll(extra);
  return headers;
}

/// Outcome of a discovery attempt, carrying enough detail to explain a failure.
class DiscoveryResult {
  const DiscoveryResult(this.ids, this.endpoint, this.error);

  final List<String> ids;
  final String endpoint;
  final String? error;

  bool get ok => error == null;
}

/// Asks an OpenAI-compatible, Anthropic, or Google endpoint what models it has.
///
/// Returns the endpoint it tried even on failure, so the UI can show what was
/// actually requested rather than a bare "failed".
Future<DiscoveryResult> discoverModels({
  required String baseUrl,
  required String api,
  String? apiKey,
  Map<String, String> headers = const {},
  Duration timeout = const Duration(seconds: 15),
}) async {
  if (baseUrl.trim().isEmpty) {
    return const DiscoveryResult([], '', 'No base URL yet.');
  }

  var uri = discoveryUri(baseUrl, api);
  final requestHeaders = discoveryHeaders(
    api: api,
    apiKey: apiKey,
    extra: headers,
  );
  if (api == 'google-generative-ai' && apiKey != null && apiKey.isNotEmpty) {
    uri = uri.replace(queryParameters: {...uri.queryParameters, 'key': apiKey});
  }

  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(uri).timeout(timeout);
    requestHeaders.forEach(request.headers.set);
    final response = await request.close().timeout(timeout);
    final body = await response.transform(utf8.decoder).join().timeout(timeout);

    if (response.statusCode >= 400) {
      return DiscoveryResult(
        const [],
        uri.toString(),
        'HTTP ${response.statusCode} from ${uri.host}. '
            '${_hintForStatus(response.statusCode)}',
      );
    }
    final ids = parseModelIds(body);
    if (ids.isEmpty) {
      return DiscoveryResult(
        const [],
        uri.toString(),
        'The endpoint answered, but no model ids were found in the response. '
            'Add models by hand instead.',
      );
    }
    return DiscoveryResult(ids, uri.toString(), null);
  } on SocketException catch (e) {
    return DiscoveryResult(
      const [],
      uri.toString(),
      'Could not reach ${uri.host}: ${e.message}',
    );
  } on HandshakeException {
    return DiscoveryResult(
      const [],
      uri.toString(),
      'TLS handshake with ${uri.host} failed.',
    );
  } catch (e) {
    return DiscoveryResult(const [], uri.toString(), '$e');
  } finally {
    client.close(force: true);
  }
}

String _hintForStatus(int status) {
  if (status == 401 || status == 403) {
    return 'The provider rejected the API key in this file.';
  }
  if (status == 404) {
    return 'That path is not where this server lists models.';
  }
  return '';
}
