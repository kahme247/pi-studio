import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_studio/pi/pi_runtime.dart';

/// The release workflow stages `pi_runtime/` next to the app executable and
/// PiRuntime has to pick it up from there: bundled node + rpc-entry present
/// means bundled backend, anything missing means fall back to `pi` on PATH
/// (which is also what every local dev build uses — they never stage it).
///
/// Only `PiRuntime.bundledIn` is exercised here: `resolve()` reads the real
/// `Platform.resolvedExecutable`, which the test runner cannot fake.
void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pi_runtime_test');
  });

  tearDown(() async {
    await root.delete(recursive: true);
  });

  Future<Directory> stageRuntime() async {
    final runtime = Directory(
      '${root.path}${Platform.pathSeparator}pi_runtime',
    );
    final nodeName = Platform.isWindows ? 'node.exe' : 'node';
    await File(
      '${runtime.path}${Platform.pathSeparator}bin${Platform.pathSeparator}$nodeName',
    ).create(recursive: true);
    await File(
      '${runtime.path}${Platform.pathSeparator}dist${Platform.pathSeparator}bundle${Platform.pathSeparator}rpc-entry.js',
    ).create(recursive: true);
    return runtime;
  }

  test('bundled backend when node and rpc-entry are staged', () async {
    await stageRuntime();
    final backend = PiRuntime.bundledIn(root.path);
    expect(backend, isNotNull);
    final bundled = backend!;
    expect(bundled.runInShell, isFalse);
    // That rpc entry forces `--mode rpc` itself (see dist/bundle/rpc-entry.js
    // in the pi package), so no extra flag is passed.
    expect(bundled.baseArgs.single, endsWith('rpc-entry.js'));
    expect(bundled.label, contains('bundled pi'));
  });

  test('version stamp surfaces in the label when present', () async {
    final runtime = await stageRuntime();
    await File('${runtime.path}${Platform.pathSeparator}PI_VERSION')
        .writeAsString('pi 0.87.0 staged just now');
    final stamped = PiRuntime.bundledIn(root.path);
    expect(stamped!.label, contains('0.87.0'));
  });

  test('null when the runtime is absent', () {
    expect(PiRuntime.bundledIn(root.path), isNull);
  });

  test('null when node is missing', () async {
    final runtime = Directory(
      '${root.path}${Platform.pathSeparator}pi_runtime',
    );
    await File(
      '${runtime.path}${Platform.pathSeparator}dist${Platform.pathSeparator}bundle${Platform.pathSeparator}rpc-entry.js',
    ).create(recursive: true);
    expect(PiRuntime.bundledIn(root.path), isNull);
  });

  test('null when rpc-entry is missing', () async {
    final runtime = Directory(
      '${root.path}${Platform.pathSeparator}pi_runtime',
    );
    final nodeName = Platform.isWindows ? 'node.exe' : 'node';
    await File(
      '${runtime.path}${Platform.pathSeparator}bin${Platform.pathSeparator}$nodeName',
    ).create(recursive: true);
    expect(PiRuntime.bundledIn(root.path), isNull);
  });
}
