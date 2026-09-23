import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pi_studio/pi/pi_runtime.dart';
import 'package:pi_studio/settings/pi_packages.dart';

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
    await File('${runtime.path}${Platform.pathSeparator}package.json')
        .writeAsString('{"version":"0.87.1"}');
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
    await File('${runtime.path}${Platform.pathSeparator}package.json').delete();
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

  test('runtime update only activates a matching installed package', () async {
    final runtime = await stageRuntime();
    await File('${runtime.path}${Platform.pathSeparator}package.json')
        .writeAsString('{"version":"0.87.1"}');
    final updates = Directory('${root.path}${Platform.pathSeparator}updates');
    final versionDir = '0.87.2-123456';
    final packageRoot =
        '${updates.path}${Platform.pathSeparator}$versionDir'
        '${Platform.pathSeparator}node_modules${Platform.pathSeparator}'
        '@earendil-works${Platform.pathSeparator}pi-coding-agent';
    final manifest = File('$packageRoot/package.json');
    await manifest.create(recursive: true);
    await manifest.writeAsString('{"version":"0.87.2"}');
    await File(
      '$packageRoot${Platform.pathSeparator}dist${Platform.pathSeparator}'
      'bundle${Platform.pathSeparator}rpc-entry.js',
    ).create(recursive: true);
    await File(
      '$packageRoot${Platform.pathSeparator}dist${Platform.pathSeparator}'
      'bundle${Platform.pathSeparator}cli.js',
    ).create();
    await File('${updates.path}${Platform.pathSeparator}current.json')
        .writeAsString('{"version":"0.87.2","directory":"$versionDir"}');

    expect(
      PiRuntime.activePackageRootIn(root.path, updatesDirectory: updates.path),
      packageRoot,
    );
    expect(
      PiRuntime.bundledVersion(
        exeDir: root.path,
        updatesDirectory: updates.path,
      ),
      '0.87.2',
    );
    final backend = PiRuntime.bundledIn(
      root.path,
      updatesDirectory: updates.path,
    );
    expect(
      backend!.baseArgs.single,
      endsWith(
        'dist${Platform.pathSeparator}bundle${Platform.pathSeparator}rpc-entry.js',
      ),
    );
  });

  test('invalid update marker falls back to the app bundle', () async {
    final runtime = await stageRuntime();
    final updates = Directory('${root.path}${Platform.pathSeparator}updates');
    await updates.create();
    await File('${updates.path}${Platform.pathSeparator}current.json')
        .writeAsString('{"version":"0.87.2","directory":"..\\\\evil"}');

    expect(
      PiRuntime.activePackageRootIn(root.path, updatesDirectory: updates.path),
      runtime.path,
    );
  });

  test('semantic runtime versions compare prereleases correctly', () {
    expect(PiRuntime.isNewerVersion('1.0.0', '1.0.0-rc.1'), isTrue);
    expect(PiRuntime.isNewerVersion('1.0.0-rc.2', '1.0.0-rc.1'), isTrue);
    expect(PiRuntime.isNewerVersion('1.0.0-rc.1', '1.0.0'), isFalse);
    expect(PiRuntime.isNewerVersion('1.0.0', '1.0.0'), isFalse);
    expect(PiRuntime.isNewerVersion('1.0.0+build.2', '1.0.0+build.1'), isFalse);
    expect(PiRuntime.isNewerVersion('1.0.0-rc.2', '1.0.0-rc.10'), isFalse);
  });

  test('updated package also drives one-shot CLI resolution', () async {
    final runtime = await stageRuntime();
    final nodeName = Platform.isWindows ? 'node.exe' : 'node';
    final node = File(
      '${runtime.path}${Platform.pathSeparator}bin${Platform.pathSeparator}$nodeName',
    );
    final base =
        '${runtime.path}${Platform.pathSeparator}dist${Platform.pathSeparator}bundle';
    final cli = File('$base${Platform.pathSeparator}cli.js');
    await cli.create(recursive: true);

    final updates = Directory('${root.path}${Platform.pathSeparator}updates');
    final versionDir = '0.87.2-123456';
    final packageRoot =
        '${updates.path}${Platform.pathSeparator}$versionDir'
        '${Platform.pathSeparator}node_modules${Platform.pathSeparator}'
        '@earendil-works${Platform.pathSeparator}pi-coding-agent';
    final manifest = File('$packageRoot/package.json');
    await manifest.create(recursive: true);
    await manifest.writeAsString('{"version":"0.87.2"}');
    final updatedCli = File(
      '$packageRoot${Platform.pathSeparator}dist${Platform.pathSeparator}'
      'bundle${Platform.pathSeparator}cli.js',
    );
    await updatedCli.create(recursive: true);
    await File(
      '$packageRoot${Platform.pathSeparator}dist${Platform.pathSeparator}'
      'bundle${Platform.pathSeparator}rpc-entry.js',
    ).create();
    await File('${updates.path}${Platform.pathSeparator}current.json')
        .writeAsString('{"version":"0.87.2","directory":"$versionDir"}');

    final resolved = PiCli.bundledCliIn(
      root.path,
      updatesDirectory: updates.path,
    );
    expect(resolved, (node.path, updatedCli.path));
  });
}
