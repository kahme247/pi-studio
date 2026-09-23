import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../pi/pi_runtime.dart';

/// How to reach the `pi` package manager CLI.
///
/// Mirrors [PiBackend] resolution in `pi_runtime.dart`, but for one-shot CLI
/// commands (`list`, `install`, `remove`, `update`) instead of the long-lived
/// `--mode rpc` session. The bundled `pi_runtime/` tree wins; otherwise `pi`
/// on PATH is used (same rule local dev builds rely on).
class PiCli {
  PiCli({String? executable, List<String>? baseArgs, bool? runInShell})
      : executable = executable ?? 'pi',
        baseArgs = baseArgs ?? const [],
        runInShell = runInShell ??
            (Platform.isWindows && !_looksLikePath(executable ?? 'pi'));

  /// Absolute path or bare command of the pi CLI.
  final String executable;

  /// Args that always precede the package command. Empty for a system `pi`;
  /// `[rpc-entry-like cli.js]`-style entries are NOT usable here — package
  /// commands need the real CLI, so the bundled backend resolves node +
  /// `dist/bundle/cli.js`.
  final List<String> baseArgs;
  final bool runInShell;

  static bool _looksLikePath(String value) =>
      value.contains('/') || value.contains(r'\');

  /// Testable bundled probe: node + `dist/bundle/cli.js` under [exeDir],
  /// else null. Shares the node lookup with `PiRuntime.bundledRoot` so there
  /// is exactly one place that knows the staged layout.
  static (String, String)? bundledCliIn(
    String exeDir, {
    String? updatesDirectory,
  }) {
    final root = PiRuntime.bundledRoot(exeDir);
    if (root == null) return null;
    final packageRoot =
        PiRuntime.activePackageRootIn(
          exeDir,
          updatesDirectory: updatesDirectory,
        ) ??
        root;
    try {
      final sep = Platform.pathSeparator;
      final nodeName = Platform.isWindows ? 'node.exe' : 'node';
      final node = File('$root${sep}bin$sep$nodeName');
      final cli = File('$packageRoot${sep}dist${sep}bundle${sep}cli.js');
      if (node.existsSync() && cli.existsSync()) {
        return (node.path, cli.path);
      }
    } on FileSystemException {
      // Ignore; fall back to PATH.
    }
    return null;
  }

/// Bundled `node <pi_runtime>/dist/bundle/cli.js` when staged next to the
/// running executable, else null (caller falls back to `pi` on PATH).
  static (String, String)? _bundledCli() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return bundledCliIn(exeDir);
  }

  /// Resolve the CLI the way the app should invoke it: bundled node + cli.js
  /// when staged, bare `pi` on PATH otherwise, `PI_STUDIO_PI` override first.
  static PiCli resolve() {
    final override = Platform.environment['PI_STUDIO_PI'];
    if (override != null && override.trim().isNotEmpty) {
      final exe = override.trim();
      return PiCli(
        executable: exe,
        runInShell: Platform.isWindows && !_looksLikePath(exe),
      );
    }
    final bundled = _bundledCli();
    if (bundled != null) {
      return PiCli(executable: bundled.$1, baseArgs: [bundled.$2]);
    }
    return PiCli(executable: 'pi');
  }

  Future<PiCliResult> run(
    List<String> args, {
    Duration? timeout,
    String? workingDirectory,
  }) async {
    Process? process;
    try {
      // Process.start (not Process.run) so a timeout actually kills the
      // child: otherwise a timed-out `pi install` keeps rewriting
      // settings.json in the background while the UI reports failure.
      process = await Process.start(
        executable,
        [...baseArgs, ...args],
        runInShell: runInShell,
        workingDirectory: workingDirectory,
      );
      final stdoutFuture = process.stdout.transform(utf8.decoder).join();
      final stderrFuture = process.stderr.transform(utf8.decoder).join();
      Future<int> exitFuture = process.exitCode;
      if (timeout != null) {
        exitFuture = exitFuture.timeout(timeout, onTimeout: () {
          process?.kill();
          throw TimeoutException('pi timed out after $timeout', timeout);
        });
      }
      final exitCode = await exitFuture;
      final stdout = await stdoutFuture;
      final stderr = await stderrFuture;
      return PiCliResult(exitCode, stdout, stderr);
    } on ProcessException catch (e) {
      process?.kill();
      return PiCliResult(-1, '', 'Could not start pi: $e');
    } on TimeoutException catch (e) {
      process?.kill();
      return PiCliResult(-1, '', 'pi timed out: $e');
    } catch (e) {
      // Callers await without try/catch and reset busy flags after; an
      // unexpected throw would wedge the UI on a spinner.
      process?.kill();
      return PiCliResult(-1, '', 'pi failed: $e');
    }
  }
}

class PiCliResult {
  PiCliResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get ok => exitCode == 0;

  String get output => (stdout + stderr).trim();
}

/// One configured package, as reported by `pi list`.
///
/// `pi list` prints sections (`User packages:` / `Project packages:`) with
/// `  <source>` rows followed by an optional dimmed `    <installedPath>`
/// row. There is no `--json` flag, so this parses that text shape.
class PiPackage {
  PiPackage({
    required this.source,
    required this.scope,
    this.installedPath,
    this.filtered = false,
  });

  final String source;
  final String scope; // 'user' | 'project'
  final String? installedPath;
  final bool filtered;

  /// `npm:@scope/name`, `npm:name`, `git:...`, URL, or local path.
  String get kind {
    final lower = source.toLowerCase();
    if (lower.startsWith('npm:')) return 'npm';
    if (source.startsWith('git:') ||
        source.startsWith('https://') ||
        source.startsWith('http://') ||
        source.startsWith('ssh://') ||
        source.startsWith('git://') ||
        source.startsWith('git@')) {
      return 'git';
    }
    return 'local';
  }

  /// Bare npm name without the `npm:` prefix or `@version` pin.
  String? get npmName {
    if (!source.toLowerCase().startsWith('npm:')) return null;
    var name = source.substring('npm:'.length);
    final at = name.lastIndexOf('@');
    // Keep scoped names (`@scope/pkg`): only strip when `@` is not leading.
    if (at > 0) name = name.substring(0, at);
    return name;
  }

  @override
  String toString() =>
      'PiPackage(source: $source, scope: $scope, path: $installedPath)';
}

/// Parses `pi list` stdout into packages.
///
/// Shape (chalk colour codes stripped first):
/// ```
/// User packages:
///   npm:foo
///     C:\path\to\foo
/// Project packages:
///   git:github.com/user/repo
/// ```
List<PiPackage> parsePiList(String stdout) {
  final clean = stdout.replaceAll(RegExp('\x1B\\[[0-9;]*m'), '');
  final sectionPattern = RegExp(
    r'^\s*(user|project)\s+packages.*?\s*:\s*$',
    caseSensitive: false,
  );
  final filteredPattern = RegExp(r'\s+\(filtered\)\s*$', caseSensitive: false);
  final packages = <PiPackage>[];
  var scope = 'user';
  PiPackage? current;

  void commit() {
    if (current != null && current!.source.isNotEmpty) {
      packages.add(current!);
    }
    current = null;
  }

  for (final rawLine in clean.split('\n')) {
    final line = rawLine.replaceAll('\r', '');
    if (line.trim().isEmpty) continue;
    final lowered = line.trim().toLowerCase();
    final section = sectionPattern.firstMatch(line);
    if (section != null) {
      commit();
      scope = section.group(1)!.toLowerCase();
      continue;
    }
    if (lowered == 'no packages installed.') continue;
    final indent = line.length - line.trimLeft().length;
    final text = line.trim();
    if (indent >= 4 && current != null && current!.installedPath == null) {
      // Deep row under a package: either the dimmed install path or a
      // wrapped continuation line. Only attach path-shaped text — a wrap
      // is ignored outright so it never becomes a phantom package row
      // (with a working Remove button pointing at garbage).
      if (_looksLikeInstallPath(text)) {
        current = PiPackage(
          source: current!.source,
          scope: current!.scope,
          installedPath: text,
          filtered: current!.filtered,
        );
      }
    } else if (indent >= 2) {
      commit();
      final filtered = filteredPattern.hasMatch(text);
      final source =
          filtered ? text.replaceFirst(filteredPattern, '').trim() : text;
      current = PiPackage(source: source, scope: scope, filtered: filtered);
    } else {
      // Unindented unknown line — ignore rather than misparse.
    }
  }
  commit();
  return packages;
}

/// Guards the 4-space indented row: only treat it as an install path when it
/// looks like one, so wrapped source text or warnings never become paths.
bool _looksLikeInstallPath(String text) =>
    text.startsWith('/') ||
    text.startsWith(r'\\') ||
    RegExp(r'^[A-Za-z]:[\\/]').hasMatch(text) ||
    text.startsWith('~');

/// One npm registry hit for the `pi-package` keyword catalog.
class NpmCatalogEntry {
  NpmCatalogEntry({
    required this.name,
    required this.version,
    required this.description,
    this.maintainers = const [],
  });

  final String name;
  final String version;
  final String description;
  final List<String> maintainers;

  String get installSource => 'npm:$name';

  factory NpmCatalogEntry.fromJson(Map<String, dynamic> json) {
    final package = json['package'] as Map<String, dynamic>? ?? {};
    final maintainers = <String>[];
    for (final m in (package['maintainers'] as List? ?? const [])) {
      if (m is Map && m['username'] is String) {
        maintainers.add(m['username'] as String);
      }
    }
    return NpmCatalogEntry(
      name: '${package['name'] ?? ''}',
      version: '${package['version'] ?? ''}',
      description: '${package['description'] ?? ''}',
      maintainers: maintainers,
    );
  }
}

/// Page of npm registry search results.
class NpmCatalogPage {
  NpmCatalogPage({
    required this.entries,
    required this.total,
  });

  final List<NpmCatalogEntry> entries;
  final int total;
}

/// Searches the public npm registry for `pi-package` keyword packages.
///
/// Uses `https://registry.npmjs.org/-/v1/search?text=keywords:pi-package`,
/// the same discoverability keyword pi documents for its package gallery.
/// `HttpClient` from `dart:io` keeps this dependency-free.
Future<NpmCatalogPage> searchNpmCatalog({
  String query = '',
  int size = 20,
  int from = 0,
  Duration timeout = const Duration(seconds: 15),
  HttpClient? client,
}) {
  final owned = client == null;
  final http = client ?? HttpClient();
  if (owned) http.connectionTimeout = timeout;
  final text = query.trim().isEmpty
      ? 'keywords:pi-package'
      : 'keywords:pi-package $query';
  final uri = Uri.https('registry.npmjs.org', '/-/v1/search', {
    'text': text,
    'size': '${size.clamp(1, 100)}',
    'from': '${from < 0 ? 0 : from}',
  });
  return http
      .getUrl(uri)
      .timeout(timeout)
      .then((request) => request.close().timeout(timeout))
      .then((response) async {
    if (response.statusCode != 200) {
      throw HttpException(
        response.statusCode == 429
            ? 'npm registry rate-limited this client — retry in a moment'
            : 'npm registry returned HTTP ${response.statusCode}',
        uri: uri,
      );
    }
    final body =
        await response.transform(utf8.decoder).join().timeout(timeout);
    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(body) as Map<String, dynamic>;
    } on FormatException {
      throw HttpException(
        'npm registry returned an unreadable response — retry',
        uri: uri,
      );
    }
    final objects = decoded['objects'];
    if (objects is! List) {
      throw HttpException(
        'npm registry returned an unexpected response shape — retry',
        uri: uri,
      );
    }
    final entries = objects
        .whereType<Map<String, dynamic>>()
        .map(NpmCatalogEntry.fromJson)
        .where((entry) => entry.name.isNotEmpty)
        .toList();
    return NpmCatalogPage(
      entries: entries,
      total: (decoded['total'] as num?)?.toInt() ?? entries.length,
    );
  }).whenComplete(() {
    if (owned) http.close();
  });
}

/// Fetches the npm registry packument for one package: description, readme,
/// versions, and time stamps.
///
/// This hits the full document endpoint (`/:pkg`, not `/:pkg/latest`)
/// because only the packument carries the `readme` field the detail sheet
/// renders. Single-package fetch, so the larger payload is acceptable.
Future<Map<String, dynamic>> fetchNpmDoc(
  String name, {
  Duration timeout = const Duration(seconds: 15),
  HttpClient? client,
}) {
  final owned = client == null;
  final http = client ?? HttpClient();
  if (owned) http.connectionTimeout = timeout;
  // pathSegments (not string interpolation): a scoped `@scope/pkg` stays one
  // encoded segment (`/@scope%2fpkg`), which is what the registry expects.
  final uri = Uri(
    scheme: 'https',
    host: 'registry.npmjs.org',
    pathSegments: [name],
  );
  return http
      .getUrl(uri)
      .timeout(timeout)
      .then((request) => request.close().timeout(timeout))
      .then((response) async {
    if (response.statusCode != 200) {
      throw HttpException(
        response.statusCode == 429
            ? 'npm registry rate-limited this client — retry in a moment'
            : 'npm registry returned HTTP ${response.statusCode} for $name',
        uri: uri,
      );
    }
    final body =
        await response.transform(utf8.decoder).join().timeout(timeout);
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } on FormatException {
      throw HttpException(
        'npm registry returned an unreadable document for $name — retry',
        uri: uri,
      );
    }
  }).whenComplete(() {
    if (owned) http.close();
  });
}
