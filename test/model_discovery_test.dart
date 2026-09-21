import 'package:flutter_test/flutter_test.dart';
import 'package:pi_studio/settings/model_discovery.dart';

/// Discovery has to resolve pi's config-value syntax before it can call a
/// provider, and it has to read back whatever shape the endpoint answers with.
/// Both are pure functions, so they are worth pinning down: getting the value
/// syntax wrong sends a literal "$MY_KEY" as a bearer token.
void main() {
  const env = {'MY_KEY': 'sk-live-123', 'HOST': 'example.com'};

  group('expandConfigValue', () {
    test('passes a literal through', () {
      expect(expandConfigValue('sk-literal', env).value, 'sk-literal');
    });

    test(r'interpolates $VAR and ${VAR}', () {
      expect(expandConfigValue(r'$MY_KEY', env).value, 'sk-live-123');
      expect(expandConfigValue(r'${MY_KEY}', env).value, 'sk-live-123');
    });

    test('interpolates inside a larger literal', () {
      expect(
        expandConfigValue(r'Bearer $MY_KEY!', env).value,
        'Bearer sk-live-123!',
      );
      expect(
        expandConfigValue(r'https://${HOST}/v1', env).value,
        'https://example.com/v1',
      );
    });

    test(r'$$ is a literal dollar and $! a literal bang', () {
      expect(expandConfigValue(r'$$MY_KEY', env).value, r'$MY_KEY');
      expect(expandConfigValue(r'$!hello', env).value, '!hello');
    });

    test('an unset variable leaves the value unresolved', () {
      final result = expandConfigValue(r'$NOPE', env);
      expect(result.ok, isFalse);
      expect(result.reason, contains('NOPE'));
    });

    test('a shell command is refused rather than executed', () {
      // pi runs these at request time. Populating a dropdown is not worth
      // running arbitrary commands out of a config file.
      final result = expandConfigValue("!op read 'op://vault/key'", env);
      expect(result.ok, isFalse);
      expect(result.reason, contains('shell command'));
    });

    test('a lone dollar survives', () {
      expect(expandConfigValue('100% \$', env).value, '100% \$');
    });
  });

  group('parseModelIds', () {
    test('reads the OpenAI shape', () {
      expect(
        parseModelIds('{"data":[{"id":"b"},{"id":"a"}]}'),
        ['a', 'b'],
      );
    });

    test('reads the Google shape and strips the models/ prefix', () {
      expect(
        parseModelIds('{"models":[{"name":"models/gemini-2.5-pro"}]}'),
        ['gemini-2.5-pro'],
      );
    });

    test('reads a bare array of id strings', () {
      expect(parseModelIds('["m1","m2"]'), ['m1', 'm2']);
    });

    test('deduplicates and drops blanks', () {
      expect(
        parseModelIds('{"data":[{"id":"a"},{"id":"a"},{"id":"  "},"b"]}'),
        ['a', 'b'],
      );
    });

    test('returns nothing for an unparseable body', () {
      expect(parseModelIds('<html>nope</html>'), isEmpty);
      expect(parseModelIds('{"unexpected":true}'), isEmpty);
    });
  });

  group('discoveryUri', () {
    test('appends /models for OpenAI-compatible bases', () {
      expect(
        discoveryUri('http://localhost:11434/v1', 'openai-completions')
            .toString(),
        'http://localhost:11434/v1/models',
      );
    });

    test('trims a trailing slash', () {
      expect(
        discoveryUri('https://openrouter.ai/api/v1/', 'openai-completions')
            .toString(),
        'https://openrouter.ai/api/v1/models',
      );
    });

    test('Anthropic needs /v1/models, once', () {
      expect(
        discoveryUri('https://api.anthropic.com', 'anthropic-messages')
            .toString(),
        'https://api.anthropic.com/v1/models',
      );
      expect(
        discoveryUri('https://api.anthropic.com/v1', 'anthropic-messages')
            .toString(),
        'https://api.anthropic.com/v1/models',
      );
    });
  });

  group('discoveryHeaders', () {
    test('sends a bearer token for OpenAI-compatible providers', () {
      final headers = discoveryHeaders(
        api: 'openai-completions',
        apiKey: 'sk-1',
      );
      expect(headers['authorization'], 'Bearer sk-1');
    });

    test('sends x-api-key and a version for Anthropic', () {
      final headers = discoveryHeaders(
        api: 'anthropic-messages',
        apiKey: 'sk-1',
      );
      expect(headers['x-api-key'], 'sk-1');
      expect(headers['anthropic-version'], isNotNull);
      expect(headers.containsKey('authorization'), isFalse);
    });

    test('omits auth entirely when there is no key', () {
      final headers = discoveryHeaders(api: 'openai-completions', apiKey: null);
      expect(headers.containsKey('authorization'), isFalse);
    });

    test('provider headers win over the generated ones', () {
      final headers = discoveryHeaders(
        api: 'openai-completions',
        apiKey: 'sk-1',
        extra: {'authorization': 'Custom scheme'},
      );
      expect(headers['authorization'], 'Custom scheme');
    });
  });

  test('an empty base URL fails before any request is made', () async {
    final result = await discoverModels(baseUrl: '  ', api: 'openai-completions');
    expect(result.ok, isFalse);
    expect(result.error, contains('No base URL'));
  });
}
