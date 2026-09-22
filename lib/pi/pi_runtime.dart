import 'dart:io';

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

  /// Returns the bundled backend if [exeDir] sits next to a staged
  /// `pi_runtime/` tree, else null. Takes the directory as a parameter (rather
  /// than reading `Platform.resolvedExecutable` itself) so tests can point it
  /// at temp dirs.
  static PiBackend? bundledIn(String exeDir) {
    final root = bundledRoot(exeDir);
    if (root == null) return null;
    final sep = Platform.pathSeparator;
    final nodeName = Platform.isWindows ? 'node.exe' : 'node';
    final node = File('$root${sep}bin$sep$nodeName');
    final entry = File(
      '$root${sep}dist${sep}bundle${sep}rpc-entry.js',
    );
    if (!entry.existsSync()) return null;
    var version = '';
    try {
      version = File('$root${sep}PI_VERSION').readAsStringSync().trim();
    } on FileSystemException {
      // Missing version stamp: still usable, just unlabeled.
    } on ArgumentError {
      // Empty path edge; ignore.
    }
    return PiBackend(
      executable: node.path,
      baseArgs: [entry.path],
      // Direct path to node: never needs the shell.
      runInShell: false,
      label: version.isEmpty ? 'bundled pi' : 'bundled pi $version',
    );
  }
}
