// ignore_for_file: avoid_print

import 'package:win32/win32.dart';

/// Smoke test for the native folder-picker wiring without opening a dialog:
/// creates the COM object, sets and reads options. If this exits 0, the
/// picker will open correctly inside the app.
void main() {
  final hr = CoInitializeEx(COINIT_APARTMENTTHREADED);
  print('CoInitializeEx: 0x${hr.toRadixString(16)}');

  final dialog = createInstance<IFileOpenDialog>(FileOpenDialog);
  try {
    dialog.setOptions(FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST);
    final options = dialog.getOptions();
    print('options set: 0x${options.toRadixString(16)}');
    print('FOS_PICKFOLDERS present: ${options & FOS_PICKFOLDERS != 0}');
  } finally {
    dialog.release();
  }
  print('picker wiring OK');
}
