import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

const _hresultCancelled = -2147023673; // 0x800704C7 ERROR_CANCELLED

/// Folder picker: uses Win32 IFileOpenDialog on Windows, zenity/kdialog on
/// Linux, or null for fallback.
String? pickFolder({String title = 'Select a folder'}) {
  if (Platform.isWindows) {
    return _showDialog(
      FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST,
      title,
    );
  }
  if (Platform.isLinux) {
    return _showLinuxDialog(directory: true, title: title);
  }
  return null;
}

/// File picker: uses Win32 IFileOpenDialog on Windows, zenity/kdialog on
/// Linux, or null for fallback.
String? pickFile({String title = 'Add file'}) {
  if (Platform.isWindows) {
    return _showDialog(
      FOS_FILEMUSTEXIST | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST,
      title,
    );
  }
  if (Platform.isLinux) {
    return _showLinuxDialog(directory: false, title: title);
  }
  return null;
}

String? _showLinuxDialog({required bool directory, required String title}) {
  try {
    final result = Process.runSync('zenity', [
      '--file-selection',
      if (directory) '--directory',
      '--title=$title',
    ]);
    if (result.exitCode == 0) {
      final path = '${result.stdout}'.trim();
      if (path.isNotEmpty) return path;
    }
  } catch (_) {
    // zenity not available, try kdialog
    try {
      final result = Process.runSync('kdialog', [
        if (directory) '--getexistingdirectory' else '--getopenfilename',
        '.',
      ]);
      if (result.exitCode == 0) {
        final path = '${result.stdout}'.trim();
        if (path.isNotEmpty) return path;
      }
    } catch (_) {
      // Fallback
    }
  }
  return null;
}

/// Must be called from the main thread (the Flutter Windows runner already
/// initializes COM).
String? _showDialog(FILEOPENDIALOGOPTIONS options, String title) {
  final dialog = createInstance<IFileOpenDialog>(FileOpenDialog);
  try {
    dialog.setOptions(options);
    final titlePtr = title.toPcwstr(allocator: calloc);
    try {
      dialog.setTitle(titlePtr);
    } finally {
      calloc.free(titlePtr);
    }

    try {
      dialog.show(GetActiveWindow());
    } on WindowsException catch (error) {
      if (error.hr == _hresultCancelled) return null;
      rethrow;
    }

    final item = dialog.getResult();
    if (item == null) return null;
    final pathPtr = item.getDisplayName(SIGDN_FILESYSPATH);
    if (pathPtr == nullptr) return null;
    try {
      return pathPtr.toDartString();
    } finally {
      CoTaskMemFree(pathPtr);
    }
  } finally {
    dialog.release();
  }
}
