import 'dart:convert';
import 'dart:io';

/// Persists a small list of paths (project folders, archived sessions) as
/// JSON under %APPDATA%\pi_studio\.
class PathListStore {
  PathListStore._(this._file);

  final File _file;

  static PathListStore open(String fileName) {
    final base = Platform.environment['APPDATA'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    final dir = Directory('$base${Platform.pathSeparator}pi_studio');
    return PathListStore._(
      File('${dir.path}${Platform.pathSeparator}$fileName'),
    );
  }

  Future<List<String>> load() async {
    try {
      if (!await _file.exists()) return [];
      final decoded = jsonDecode(await _file.readAsString());
      if (decoded is List) {
        return decoded.whereType<String>().toList();
      }
    } on FormatException {
      // Corrupt file: start clean rather than crash.
    } on FileSystemException {
      // Unreadable: treat as empty.
    }
    return [];
  }

  Future<void> save(List<String> paths) async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(paths),
      );
    } on FileSystemException {
      // Persistence is best-effort; the app works without it.
    }
  }
}
