import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../pi/session_store.dart';

/// Reads and writes pi's global settings file (`~/.pi/agent/settings.json`).
///
/// Every write is a read-modify-write of the parsed map, so keys this UI knows
/// nothing about — `subagents`, `tokenSpeed`, `modelThinkingLevels`, package
/// filters, anything a future pi adds — survive untouched. Writing blind JSON
/// from a fixed schema would silently delete them.
///
/// The previous revision is kept alongside as `settings.json.bak`, because this
/// file holds configuration the user cannot easily reconstruct.
class PiSettings extends ChangeNotifier {
  /// [filePath] overrides the location, which tests use to avoid touching the
  /// real settings file.
  PiSettings({String? filePath})
      : path = filePath ?? defaultPath,
        _data = <String, dynamic>{},
        _loading = true;

  /// A store that never touches the filesystem.
  ///
  /// Widget tests need this: they run in a fake-async zone where real dart:io
  /// futures never complete, so a file-backed store would leave the page stuck
  /// on its loading state and a dangling IO operation behind.
  PiSettings.inMemory({Map<String, dynamic>? data})
      : path = '',
        _data = data ?? <String, dynamic>{},
        _loading = false;

  /// Absolute path of the file being edited; empty for [PiSettings.inMemory].
  final String path;

  /// pi's global settings file.
  static String get defaultPath =>
      '${piAgentDir().path}${Platform.pathSeparator}settings.json';

  Map<String, dynamic> _data;
  bool _loading;
  bool _dirty = false;
  String? _error;

  bool get _inMemory => path.isEmpty;

  bool get loading => _loading;
  bool get dirty => _dirty;
  String? get error => _error;

  /// Every key currently in the file, including ones the UI does not model.
  List<String> get keys => _data.keys.toList()..sort();

  /// Raw snapshot of a key, for the "unmanaged keys" read-out.
  Object? raw(String key) => _data[key];

  Future<void> load() async {
    if (_inMemory) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final file = File(path);
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        _data = decoded is Map<String, dynamic>
            ? decoded
            : <String, dynamic>{};
      } else {
        _data = <String, dynamic>{};
      }
    } on FormatException {
      _error = 'settings.json is not valid JSON — fix it before editing here.';
      _data = <String, dynamic>{};
    } on FileSystemException catch (e) {
      _error = 'Could not read settings.json: ${e.message}';
      _data = <String, dynamic>{};
    }
    _dirty = false;
    _loading = false;
    notifyListeners();
  }

  /// Persists the current map, replacing the file atomically.
  Future<void> save() async {
    if (_inMemory) {
      _dirty = false;
      _error = null;
      notifyListeners();
      return;
    }
    final target = File(path);
    try {
      await target.parent.create(recursive: true);
      if (await target.exists()) {
        await target.copy('${target.path}.bak');
      }
      // Write a sibling first, then swap: an interrupted save leaves the old
      // settings intact rather than a truncated file.
      final temp = File('${target.path}.tmp');
      await temp.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(_sorted())}\n',
      );
      await temp.rename(target.path);
      _dirty = false;
      _error = null;
    } on FileSystemException catch (e) {
      _error = 'Could not save: ${e.message}';
    }
    notifyListeners();
  }

  /// Drops unsaved edits and re-reads from disk.
  Future<void> discard() async {
    if (!_dirty) return;
    await load();
  }

  // --------------------------------------------------------------- reading

  Object? read(String path) {
    Object? node = _data;
    for (final part in path.split('.')) {
      if (node is! Map) return null;
      node = node[part];
      if (node == null) return null;
    }
    return node;
  }

  bool readBool(String path, {bool fallback = false}) {
    final value = read(path);
    return value is bool ? value : fallback;
  }

  String? readString(String path) {
    final value = read(path);
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  num? readNumber(String path) {
    final value = read(path);
    return value is num ? value : null;
  }

  List<String> readList(String path) {
    final value = read(path);
    if (value is! List) return const [];
    return value.whereType<String>().toList();
  }

  // --------------------------------------------------------------- writing

  /// Writes [value] at a dotted [path]. A null [value] deletes the key, and
  /// maps left empty by that deletion are pruned so the file stays readable.
  void write(String path, Object? value) {
    final parts = path.split('.');
    if (value == null) {
      _remove(parts);
    } else {
      var node = _data;
      for (final part in parts.take(parts.length - 1)) {
        final child = node[part];
        if (child is Map<String, dynamic>) {
          node = child;
        } else {
          final created = <String, dynamic>{};
          node[part] = created;
          node = created;
        }
      }
      node[parts.last] = value;
    }
    _dirty = true;
    notifyListeners();
  }

  /// Convenience for list-valued settings; an empty list removes the key.
  void writeList(String path, List<String> values) {
    final cleaned = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    write(path, cleaned.isEmpty ? null : cleaned);
  }

  void _remove(List<String> parts) {
    final stack = <Map<String, dynamic>>[_data];
    for (final part in parts.take(parts.length - 1)) {
      final child = stack.last[part];
      if (child is! Map<String, dynamic>) return;
      stack.add(child);
    }
    stack.last.remove(parts.last);
    for (var i = stack.length - 1; i > 0; i--) {
      if (stack[i].isNotEmpty) break;
      stack[i - 1].remove(parts[i - 1]);
    }
  }

  /// pi writes its own file with sorted top-level keys; match that so saving
  /// from here produces a minimal diff.
  Map<String, dynamic> _sorted() {
    final out = <String, dynamic>{};
    for (final key in keys) {
      out[key] = _data[key];
    }
    return out;
  }
}

/// pi wants forward slashes (or escaped backslashes) in JSON paths, and a
/// literal backslash from a Windows paste is a parse error. Normalise on save.
String normalizeSettingsPath(String input) =>
    input.trim().replaceAll(r'\', '/');
