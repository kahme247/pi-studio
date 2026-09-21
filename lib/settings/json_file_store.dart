import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Deep-copies decoded JSON into plain `Map<String, dynamic>` / `List<dynamic>`.
///
/// `jsonDecode` already produces exactly that shape. Dart map and list literals
/// do not: `{'models': [{'id': 'a'}]}` infers
/// `Map<String, List<Map<String, String>>>`, and writing a differently-typed
/// value into it later throws at runtime — a trap that only shows up when
/// something other than the decoder supplies the data.
///
/// Normalising on the way in means both paths behave identically.
Object? _normalizeJson(Object? node) {
  if (node is Map) {
    final out = <String, dynamic>{};
    node.forEach((key, value) => out['$key'] = _normalizeJson(value));
    return out;
  }
  if (node is List) return node.map(_normalizeJson).toList();
  return node;
}

Map<String, dynamic> _normalizeRoot(Object? node) {
  final normalized = _normalizeJson(node);
  return normalized is Map<String, dynamic> ? normalized : <String, dynamic>{};
}

/// A JSON document that pi owns and this app edits.
///
/// Every write is a read-modify-write of the parsed map, so keys this UI knows
/// nothing about survive untouched. Writing blind JSON from a fixed schema
/// would silently delete them — and these files hold configuration the user
/// cannot easily reconstruct.
///
/// Saving replaces the file atomically and keeps the previous revision as a
/// `.bak` beside it.
///
/// Two concrete stores sit on this today: `PiSettings` over
/// `~/.pi/agent/settings.json`, and `PiModels` over `~/.pi/agent/models.json`.
abstract class JsonFileStore extends ChangeNotifier {
  /// [path] is the file to edit.
  JsonFileStore({required this.path})
      : _data = <String, dynamic>{},
        _loading = true;

  /// A store that never touches the filesystem.
  ///
  /// Widget tests need this: they run in a fake-async zone where real dart:io
  /// futures never complete, so a file-backed store would leave a page stuck on
  /// its loading state with a dangling IO operation behind it.
  JsonFileStore.inMemory({Map<String, dynamic>? data})
      : path = '',
        _data = _normalizeRoot(data ?? <String, dynamic>{}),
        _loading = false;

  /// Absolute path of the file being edited; empty for the in-memory form.
  final String path;

  Map<String, dynamic> _data;
  bool _loading;
  bool _dirty = false;
  String? _error;

  bool get _inMemory => path.isEmpty;

  bool get loading => _loading;
  bool get dirty => _dirty;
  String? get error => _error;

  /// File name, for messages shown to the user.
  String get label => path.isEmpty ? 'in-memory store' : path.split(
    Platform.pathSeparator,
  ).last;

  /// Every key currently in the file, including ones the UI does not model.
  List<String> get keys => _data.keys.toList()..sort();

  /// Raw snapshot of a key.
  Object? raw(String key) => _data[key];

  Future<void> load() async {
    if (_inMemory) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final file = File(path);
      if (await file.exists()) {
        _data = _normalizeRoot(jsonDecode(await file.readAsString()));
      } else {
        _data = <String, dynamic>{};
      }
    } on FormatException {
      _error = '$label is not valid JSON — fix it before editing here.';
      _data = <String, dynamic>{};
    } on FileSystemException catch (e) {
      _error = 'Could not read $label: ${e.message}';
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
      // file intact rather than a truncated one.
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
  ///
  /// Dotted paths cannot express a key that itself contains a dot; use
  /// [mutate] for those.
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

  /// Structured edits that a dotted path cannot express — anything keyed by
  /// user-supplied strings, where the key may contain a dot.
  ///
  /// [change] receives the live root map. Mutate it, then this marks the store
  /// dirty and notifies listeners.
  void mutate(void Function(Map<String, dynamic> data) change) {
    change(_data);
    _dirty = true;
    notifyListeners();
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

  /// pi writes its own files with sorted top-level keys; match that so saving
  /// from here produces a minimal diff.
  Map<String, dynamic> _sorted() {
    final out = <String, dynamic>{};
    for (final key in keys) {
      out[key] = _data[key];
    }
    return out;
  }
}
