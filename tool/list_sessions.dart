// ignore_for_file: avoid_print

import 'package:pi_studio/pi/session_store.dart';

/// Prints the sidebar listing so session naming can be checked without
/// launching the app: dart run tool/list_sessions.dart
Future<void> main() async {
  final sessions = await listSessions();
  print('${sessions.length} sessions');
  for (final session in sessions.take(15)) {
    print('${session.modified.toLocal().toString().split('.').first}  '
        '${session.cwd ?? '-'}');
    print('    ${session.title}');
  }
}
