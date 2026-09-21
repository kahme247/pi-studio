import 'dart:io';

import '../pi/session_store.dart';
import 'json_file_store.dart';

/// pi's global settings file, `~/.pi/agent/settings.json`.
///
/// All of the read-modify-write, atomic-save and `.bak` behaviour lives in
/// [JsonFileStore]; this type only pins the location.
class PiSettings extends JsonFileStore {
  /// [filePath] overrides the location, which tests use to avoid touching the
  /// real settings file.
  PiSettings({String? filePath}) : super(path: filePath ?? defaultPath);

  PiSettings.inMemory({super.data}) : super.inMemory();

  /// pi's global settings file.
  static String get defaultPath =>
      '${piAgentDir().path}${Platform.pathSeparator}settings.json';
}

/// pi wants forward slashes (or escaped backslashes) in JSON paths, and a
/// literal backslash from a Windows paste is a parse error. Normalise on save.
String normalizeSettingsPath(String input) =>
    input.trim().replaceAll(r'\', '/');
