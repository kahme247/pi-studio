import 'package:flutter_test/flutter_test.dart';

import 'package:pi_studio/settings/pi_packages.dart';

void main() {
  group('parsePiList', () {
    test('parses user packages with installed paths', () {
      const output = '''
User packages:
  npm:@juicesharp/rpiv-ask-user-question
    C:\\Users\\Khaled\\.pi\\agent\\npm\\node_modules\\@juicesharp\\rpiv-ask-user-question
  npm:pi-lens
    C:\\Users\\Khaled\\.pi\\agent\\npm\\node_modules\\pi-lens
''';
      final packages = parsePiList(output);
      expect(packages, hasLength(2));
      expect(packages[0].source, 'npm:@juicesharp/rpiv-ask-user-question');
      expect(packages[0].scope, 'user');
      expect(
        packages[0].installedPath,
        contains('rpiv-ask-user-question'),
      );
      expect(packages[1].source, 'npm:pi-lens');
    });

    test('parses project scope and filtered marker', () {
      const output = '''
User packages:
  npm:foo

Project packages:
  git:github.com/user/repo (filtered)
''';
      final packages = parsePiList(output);
      expect(packages, hasLength(2));
      expect(packages[0].scope, 'user');
      expect(packages[1].scope, 'project');
      expect(packages[1].source, 'git:github.com/user/repo');
      expect(packages[1].filtered, isTrue);
    });

    test('empty install reports no packages', () {
      expect(parsePiList('No packages installed.\n'), isEmpty);
      expect(parsePiList(''), isEmpty);
    });

    test('strips ANSI colour codes', () {
      const output = '\x1B[1mUser packages:\x1B[0m\n'
          '  npm:foo\n'
          '    \x1B[2m/some/path\x1B[0m\n';
      final packages = parsePiList(output);
      expect(packages, hasLength(1));
      expect(packages[0].source, 'npm:foo');
      expect(packages[0].installedPath, '/some/path');
    });

    test('wrapped continuation lines are ignored, never invent rows', () {
      // A long source wrapped by the terminal onto a 4-space indented line
      // must vanish — not become an install path, and not a phantom
      // package row with a working Remove/Update button pointing at
      // garbage text. Genuine `pi list` output never wraps this way; this
      // only triggers on narrow/redirected terminals.
      const output = '''
User packages:
  npm:averylongpackagenamethatwraps
    ontoanextline
  npm:real
    /real/path
''';
      final packages = parsePiList(output);
      expect(packages.map((p) => p.source), ['npm:averylongpackagenamethatwraps', 'npm:real']);
      expect(
        packages.firstWhere((p) => p.source == 'npm:real').installedPath,
        '/real/path',
      );
      expect(
        packages
            .firstWhere(
              (p) => p.source == 'npm:averylongpackagenamethatwraps',
            )
            .installedPath,
        isNull,
      );
    });

    test('tilde install path counts as a path row', () {
      const output = 'User packages:\n  ./local/pkg\n    ~/pi-pkgs/pkg\n';
      final packages = parsePiList(output);
      expect(packages, hasLength(1));
      expect(packages[0].installedPath, '~/pi-pkgs/pkg');
    });

    test('case-insensitive section headers and filtered marker', () {
      const output = '''
USER PACKAGES:
  npm:foo
PROJECT PACKAGES:
  npm:bar (FILTERED)
''';
      final packages = parsePiList(output);
      expect(packages, hasLength(2));
      expect(packages[0].scope, 'user');
      expect(packages[1].scope, 'project');
      expect(packages[1].source, 'npm:bar');
      expect(packages[1].filtered, isTrue);
    });

    test('windows CRLF line endings parse cleanly', () {
      const output = 'User packages:\r\n  npm:foo\r\n'
          '    C:\\x\\foo\r\n';
      final packages = parsePiList(output);
      expect(packages, hasLength(1));
      expect(packages[0].source, 'npm:foo');
      expect(packages[0].installedPath, contains('foo'));
    });

    test('stray unindented lines are ignored, sections still switch', () {
      const output = '''
User packages:
  npm:foo
some warning from pi on stdout
Project packages:
  npm:bar
''';
      final packages = parsePiList(output);
      expect(packages.map((p) => p.source), ['npm:foo', 'npm:bar']);
      expect(packages[1].scope, 'project');
    });
  });

  group('PiPackage', () {
    test('kind detects npm, git and local sources', () {
      expect(PiPackage(source: 'npm:foo', scope: 'user').kind, 'npm');
      expect(
        PiPackage(source: 'git:github.com/u/r', scope: 'user').kind,
        'git',
      );
      expect(
        PiPackage(source: 'https://github.com/u/r', scope: 'user').kind,
        'git',
      );
      expect(PiPackage(source: './local/path', scope: 'user').kind, 'local');
    });

    test('npmName strips prefix and version pin, keeps scope', () {
      expect(
        PiPackage(source: 'npm:@scope/pkg@1.2.3', scope: 'user').npmName,
        '@scope/pkg',
      );
      expect(PiPackage(source: 'npm:foo', scope: 'user').npmName, 'foo');
      expect(
        PiPackage(source: 'git:github.com/u/r', scope: 'user').npmName,
        isNull,
      );
    });
  });

  group('NpmCatalogEntry', () {
    test('fromJson reads search result shape', () {
      final entry = NpmCatalogEntry.fromJson({
        'package': {
          'name': 'pi-lens',
          'version': '4.2.1',
          'description': 'Real-time code feedback for pi',
          'maintainers': [
            {'username': 'someone'},
          ],
        },
      });
      expect(entry.name, 'pi-lens');
      expect(entry.version, '4.2.1');
      expect(entry.installSource, 'npm:pi-lens');
      expect(entry.maintainers, ['someone']);
    });
  });
}
