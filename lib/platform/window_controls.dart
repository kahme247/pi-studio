import 'dart:io';

import 'package:win32/win32.dart';

/// Window controls for the custom (frameless) title bar, straight through
/// Win32 FFI — no plugins.

const int _wmNcLButtonDown = 0x00A1;
const int _htCaption = 2;

// WM_NCHITTEST codes for resize edges/corners.
const int htLeft = 10;
const int htRight = 11;
const int htTop = 12;
const int htTopLeft = 13;
const int htTopRight = 14;
const int htBottom = 15;
const int htBottomLeft = 16;
const int htBottomRight = 17;

/// Starts a native move loop as if the user grabbed the OS title bar.
void beginWindowDrag() {
  if (!Platform.isWindows) return;
  final hwnd = GetActiveWindow();
  ReleaseCapture();
  SendMessage(hwnd, _wmNcLButtonDown, WPARAM(_htCaption), LPARAM(0));
}

/// Starts a native resize loop for the given WM_NCHITTEST edge code.
/// Flutter owns the whole client area, so the OS never sees the edges itself.
void beginWindowResize(int hitTestCode) {
  if (!Platform.isWindows) return;
  final hwnd = GetActiveWindow();
  ReleaseCapture();
  SendMessage(hwnd, _wmNcLButtonDown, WPARAM(hitTestCode), LPARAM(0));
}

void minimizeWindow() {
  if (!Platform.isWindows) return;
  ShowWindow(GetActiveWindow(), SW_MINIMIZE);
}

void toggleMaximizeWindow() {
  if (!Platform.isWindows) return;
  final hwnd = GetActiveWindow();
  ShowWindow(hwnd, IsZoomed(hwnd) ? SW_RESTORE : SW_MAXIMIZE);
}

void closeWindow() {
  if (!Platform.isWindows) return;
  PostMessage(GetActiveWindow(), WM_CLOSE, WPARAM(0), LPARAM(0));
}
