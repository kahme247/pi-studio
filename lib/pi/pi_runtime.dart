import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _piPackage = '@earendil-works/pi-coding-agent';
final _piVersionPattern = RegExp(
  r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
  r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?'
  r'(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
);

/// How to spawn the pi backend.
///
/// Bundled-first: `<exeDir>/pi_runtime/` (shipped by `tool/stage_pi_runtime.*`
/// during release packaging) holds a Node binary plus the pi bundle, so the
/// app works with no `pi` install. Otherwise falls back to `pi` on PATH,
/// which is also what local dev builds use (they never stage `pi_runtime/`).
class PiBackend {
  PiBackend({
    required this.executable,
    required this.baseArgs,
    required this.runInShell,
    required this.label,
  });

  /// Absolute path, or a bare command (`pi`) resolved via PATH.
  final String executable;

  /// Args that always precede session args. Bundled: `[rpc-entry.js]` (that
  /// entry forces `--mode rpc` itself). System: `['--mode', 'rpc']`.
  final List<String> baseArgs;
  final bool runInShell;

  /// Human-readable source, for status lines and error messages.
  final String label;
}

class PiRuntime {
  PiRuntime._();

  /// Env override: path to a `pi` executable. Wins over everything; useful
  /// for testing a different pi against a release build.
  static const overrideEnv = 'PI_STUDIO_PI';

  static Future<PiBackend> resolve() async {
    final override = Platform.environment[overrideEnv];
    if (override != null && override.trim().isNotEmpty) {
      final exe = override.trim();
      return PiBackend(
        executable: exe,
        baseArgs: const ['--mode', 'rpc'],
        // An explicit path is spawned directly; only a bare `pi` command
        // needs the shell (npm's .cmd shim on Windows).
        runInShell: Platform.isWindows && !_looksLikePath(exe),
        label: 'pi override ($exe)',
      );
    }
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return bundledIn(exeDir) ?? _pathFallback();
  }

  static bool _looksLikePath(String value) =>
      value.contains('/') || value.contains(r'\');

  static PiBackend _pathFallback() => PiBackend(
    executable: 'pi',
    baseArgs: const ['--mode', 'rpc'],
    // npm installs `pi` as a .cmd shim on Windows.
    runInShell: Platform.isWindows,
    label: 'pi on PATH',
  );

  /// Shared root probe: returns `<exeDir>/pi_runtime` when the staged node
  /// binary exists, else null. Both the RPC backend ([bundledIn]) and the
  /// one-shot package CLI (`PiCli.bundledCliIn` in settings/pi_packages.dart)
  /// build on this so node lookup lives in one place. Entry files
  /// (`rpc-entry.js` vs `cli.js`) are validated by each caller, since the
  /// backend and the CLI need different entries.
  static String? bundledRoot(String exeDir) {
    final sep = Platform.pathSeparator;
    final root = '$exeDir${sep}pi_runtime';
    final nodeName = Platform.isWindows ? 'node.exe' : 'node';
    if (!File('$root${sep}bin$sep$nodeName').existsSync()) return null;
    return root;
  }

  static String? _updatesDirectory() {
    final home = Platform.environment['HOME'];
    if (Platform.isWindows) {
      final local = Platform.environment['LOCALAPPDATA'];
      if (local == null || local.isEmpty) return null;
      return '$local${Platform.pathSeparator}PiStudio${Platform.pathSeparator}pi-updates';
    }
    if (Platform.isMacOS && home != null) {
      return '$home${Platform.pathSeparator}Library${Platform.pathSeparator}Application Support${Platform.pathSeparator}PiStudio${Platform.pathSeparator}pi-updates';
    }
    final xdg = Platform.environment['XDG_DATA_HOME'];
    final data = xdg != null && xdg.isNotEmpty
        ? xdg
        : home == null
        ? null
        : '$home${Platform.pathSeparator}.local${Platform.pathSeparator}share';
    return data == null
        ? null
        : '$data${Platform.pathSeparator}pi-studio${Platform.pathSeparator}pi-updates';
  }

  /// Current per-user Pi package, if the user installed a runtime update.
  static String? activePackageRootIn(
    String exeDir, {
    String? updatesDirectory,
  }) {
    final bundled = bundledRoot(exeDir);
    if (bundled == null) return null;
    final updates = updatesDirectory ?? _updatesDirectory();
    if (updates == null) return bundled;
    try {
      final marker = jsonDecode(
        File('$updates${Platform.pathSeparator}current.json')
            .readAsStringSync(),
      );
      if (marker is! Map<String, dynamic>) return bundled;
      final directory = marker['directory'];
      final version = marker['version'];
      if (directory is! String ||
          version is! String ||
          !_validUpdateVersion(version) ||
          !RegExp('^${RegExp.escape(version)}-[0-9]+\$').hasMatch(directory)) {
        return bundled;
      }
      final baseRoot =
          '$updates${Platform.pathSeparator}$directory'
          '${Platform.pathSeparator}node_modules${Platform.pathSeparator}'
          '@earendil-works${Platform.pathSeparator}pi-coding-agent';
      final manifest = File('$baseRoot${Platform.pathSeparator}package.json');
      final entry = File(
        '$baseRoot${Platform.pathSeparator}dist${Platform.pathSeparator}bundle${Platform.pathSeparator}rpc-entry.js',
      );
      final cli = File(
        '$baseRoot${Platform.pathSeparator}dist${Platform.pathSeparator}bundle${Platform.pathSeparator}cli.js',
      );
      final nodeName = Platform.isWindows ? 'node.exe' : 'node';
      final node = File(
        '$bundled${Platform.pathSeparator}bin${Platform.pathSeparator}$nodeName',
      );
      if (manifest.existsSync() &&
          entry.existsSync() &&
          cli.existsSync() &&
          node.existsSync()) {
        final package = jsonDecode(manifest.readAsStringSync());
        if (package is Map && package['version'] == version) {
          final bundledPackage = File(
            '$bundled${Platform.pathSeparator}package.json',
          );
          if (bundledPackage.existsSync()) {
            final bundled = jsonDecode(bundledPackage.readAsStringSync());
            final bundledVersion = bundled is Map ? bundled['version'] : null;
            if (bundledVersion is String &&
                !isNewerVersion(version, bundledVersion)) {
              return bundled;
            }
          }
          return baseRoot;
        }
      }
    } on FileSystemException {
      // No update installed, or an interrupted update marker.
    } on FormatException {
      // Ignore an unreadable marker and keep using the app's bundled version.
    } on TypeError {
      // Ignore a malformed package manifest and keep using the app's bundle.
    }
    return bundled;
  }

  static String? bundledVersion({String? exeDir, String? updatesDirectory}) {
    final dir = exeDir ?? File(Platform.resolvedExecutable).parent.path;
    final root = bundledRoot(dir);
    if (root == null) return null;
    final packageRoot =
        activePackageRootIn(dir, updatesDirectory: updatesDirectory) ?? root;
    try {
      final package = jsonDecode(
        File('$packageRoot${Platform.pathSeparator}package.json')
            .readAsStringSync(),
      );
      final version = package is Map ? package['version'] : null;
      if (version is String && _piVersionPattern.hasMatch(version)) {
        return version;
      }
    } on FileSystemException {
      // Fall through to the version stamp.
    } on FormatException {
      // Fall through to the version stamp.
    } on TypeError {
      // Fall through to the version stamp.
    }
    try {
      final stamp = File('$packageRoot${Platform.pathSeparator}PI_VERSION')
          .readAsStringSync();
      return RegExp(r'\b(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)\b')
          .firstMatch(stamp)
          ?.group(1);
    } on FileSystemException {
      return null;
    }
  }

  static bool isNewerVersion(String candidate, String current) {
    if (!_piVersionPattern.hasMatch(candidate) ||
        !_piVersionPattern.hasMatch(current)) {
      return false;
    }
    final a = candidate
        .split(RegExp(r'[-+]'))
        .first
        .split('.')
        .map(int.parse)
        .toList();
    final b = current
        .split(RegExp(r'[-+]'))
        .first
        .split('.')
        .map(int.parse)
        .toList();
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) {
        return a[i] > b[i];
      }
    }
    final build = candidate.indexOf('+');
    final stableCandidate = build < 0
        ? candidate
        : candidate.substring(0, build);
    final currentBuild = current.indexOf('+');
    final stableCurrent = currentBuild < 0
        ? current
        : current.substring(0, currentBuild);
    final ap = stableCandidate.contains('-')
        ? stableCandidate.substring(stableCandidate.indexOf('-') + 1).split('.')
        : const <String>[];
    final bp = stableCurrent.contains('-')
        ? stableCurrent.substring(stableCurrent.indexOf('-') + 1).split('.')
        : const <String>[];
    if (ap.isEmpty || bp.isEmpty) return ap.isEmpty && bp.isNotEmpty;
    for (var i = 0; i < ap.length && i < bp.length; i++) {
      if (ap[i] == bp[i]) continue;
      final an = int.tryParse(ap[i]);
      final bn = int.tryParse(bp[i]);
      if (an != null && bn != null) return an > bn;
      if (an != null) return false;
      if (bn != null) return true;
      return ap[i].compareTo(bp[i]) > 0;
    }
    return ap.length > bp.length;
  }

  static bool _validUpdateVersion(String version) =>
      _piVersionPattern.hasMatch(version) && !version.contains('+');

  static Future<String> latestVersion() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    final uri = Uri(
      scheme: 'https',
      host: 'registry.npmjs.org',
      pathSegments: [_piPackage, 'latest'],
    );
    try {
      final response =
          await (await client.getUrl(uri).timeout(const Duration(seconds: 15)))
              .close()
              .timeout(const Duration(seconds: 15));
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'npm registry returned HTTP ${response.statusCode}',
          uri: uri,
        );
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(body);
      final version = decoded is Map ? decoded['version'] : null;
      if (version is! String || !_validUpdateVersion(version)) {
        throw const FormatException(
          'npm registry returned an invalid Pi version',
        );
      }
      return version;
    } finally {
      client.close();
    }
  }

  static Future<String> updateBundled({
    String? targetVersion,
    void Function(String)? onProgress,
  }) async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final root = bundledRoot(exeDir);
    if (root == null) throw StateError('This build has no bundled Pi runtime.');
    final sep = Platform.pathSeparator;
    final node =
        '$root${sep}bin$sep${Platform.isWindows ? 'node.exe' : 'node'}';
    final npm = '$root${sep}node_modules${sep}npm${sep}bin${sep}npm-cli.js';
    if (!File(npm).existsSync()) {
      throw StateError(
        'Bundled npm is missing; install the latest Pi Studio release first.',
      );
    }

    final latest = targetVersion ?? await latestVersion();
    if (!_validUpdateVersion(latest)) {
      throw const FormatException('Invalid Pi version from npm registry');
    }
    final current = bundledVersion(exeDir: exeDir);
    if (current != null && !isNewerVersion(latest, current)) return current;

    final updates = _updatesDirectory();
    if (updates == null) {
      throw StateError('Could not determine the user data directory.');
    }
    await Directory(updates).create(recursive: true);
    final staging = await Directory(updates).createTemp('staging-');
    try {
      onProgress?.call('Downloading Pi $latest…');
      final result = await _run(node, [
        npm,
        'install',
        '--prefix',
        staging.path,
        '--ignore-scripts',
        '--no-audit',
        '--no-fund',
        '--no-update-notifier',
        '$_piPackage@$latest',
      ], timeout: const Duration(minutes: 5));
      if (result.exitCode != 0) {
        final output = '${result.stdout}${result.stderr}'.trim();
        throw StateError(output.isEmpty ? 'npm install failed' : output);
      }
      final stagingPath = staging.path;
      final packageRoot =
          '$stagingPath$sep'
          'node_modules$sep'
          '@earendil-works$sep'
          'pi-coding-agent';
      final packageManifest =
          '$packageRoot$sep'
          'package.json';
      final package = jsonDecode(File(packageManifest).readAsStringSync());
      final installed = package is Map ? package['version'] : null;
      if (installed is! String || installed != latest) {
        throw StateError('Installed Pi package has an invalid version.');
      }
      for (final entry in ['rpc-entry.js', 'cli.js']) {
        final smokeEntry =
            '$packageRoot$sep'
            'dist$sep'
            'bundle$sep'
            '$entry';
        final smoke = await _run(node, [smokeEntry, '--help']);
        if (smoke.exitCode != 0) {
          throw StateError(
            'Pi $installed failed its $entry smoke test: '
            '${smoke.stdout}${smoke.stderr}',
          );
        }
      }

      final directory = '$installed-${DateTime.now().microsecondsSinceEpoch}';
      final target = Directory('$updates$sep$directory');
      await staging.rename(target.path);
      // ponytail: retain old versions for rollback; prune once disk use matters.
      final marker = File('$updates${sep}current.json');
      final next = File(
        '$updates${sep}current-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      final backup = File(
        '$updates${sep}previous-${DateTime.now().microsecondsSinceEpoch}.json',
      );
      var oldMarkerMoved = false;
      var activated = false;
      try {
        await next.writeAsString(
          jsonEncode({'version': installed, 'directory': directory}),
          flush: true,
        );
        if (Platform.isWindows && await marker.exists()) {
          await marker.rename(backup.path);
          oldMarkerMoved = true;
        }
        try {
          await next.rename(marker.path);
        } on FileSystemException {
          if (oldMarkerMoved) await backup.rename(marker.path);
          oldMarkerMoved = false;
          rethrow;
        }
        activated = true;
        if (oldMarkerMoved) {
          oldMarkerMoved = false;
          try {
            await backup.delete();
          } on FileSystemException {
            // The new marker is active; a stale backup is harmless.
          }
        }
      } finally {
        if (await next.exists()) await next.delete();
        if (oldMarkerMoved && await backup.exists()) {
          await backup.rename(marker.path);
        }
        if (!activated && await target.exists()) {
          await target.delete(recursive: true);
        }
      }
      onProgress?.call('Pi $installed is ready for new sessions.');
      return installed;
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  static Future<ProcessResult> _run(
    String executable,
    List<String> args, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final process = await Process.start(executable, args);
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    try {
      final code = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          process.kill();
          throw TimeoutException('Pi runtime command timed out after $timeout');
        },
      );
      return ProcessResult(process.pid, code, await stdout, await stderr);
    } on TimeoutException {
      await Future.wait([stdout, stderr]);
      rethrow;
    }
  }

  /// Returns the bundled backend if [exeDir] sits next to a staged
  /// `pi_runtime/` tree, else null. Takes the directory as a parameter (rather
  /// than reading `Platform.resolvedExecutable` itself) so tests can point it
  /// at temp dirs.
  static PiBackend? bundledIn(String exeDir, {String? updatesDirectory}) {
    final root = bundledRoot(exeDir);
    if (root == null) return null;
    final packageRoot =
        activePackageRootIn(exeDir, updatesDirectory: updatesDirectory) ?? root;
    final sep = Platform.pathSeparator;
    final nodeName = Platform.isWindows ? 'node.exe' : 'node';
    final node = File('$root${sep}bin$sep$nodeName');
    final entry = File('$packageRoot${sep}dist${sep}bundle${sep}rpc-entry.js');
    if (!entry.existsSync()) return null;
    final version =
        bundledVersion(exeDir: exeDir, updatesDirectory: updatesDirectory) ??
        '';
    return PiBackend(
      executable: node.path,
      baseArgs: [entry.path],
      // Direct path to node: never needs the shell.
      runInShell: false,
      label: version.isEmpty ? 'bundled pi' : 'bundled pi $version',
    );
  }
}
