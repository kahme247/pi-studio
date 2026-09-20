import 'dart:convert';
import 'dart:io';

class PiSession {
  PiSession({
    required this.path,
    required this.title,
    required this.cwd,
    required this.modified,
  });

  final String path;
  final String title;
  final String? cwd;
  final DateTime modified;
}

Directory piAgentDir() {
  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      Directory.current.path;
  return Directory(
    '$home${Platform.pathSeparator}.pi${Platform.pathSeparator}agent',
  );
}

Directory piSessionsDir() =>
    Directory('${piAgentDir().path}${Platform.pathSeparator}sessions');

/// Lists saved pi sessions, newest first. Best-effort: unreadable files are
/// skipped rather than failing the whole listing.
Future<List<PiSession>> listSessions({int limit = 300}) async {
  final dir = piSessionsDir();
  if (!await dir.exists()) return const [];

  final files = <File>[];
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.toLowerCase().endsWith('.jsonl')) {
      files.add(entity);
    }
  }

  final sessions = <PiSession>[];
  for (final file in files) {
    try {
      final stat = await file.stat();
      sessions.add(await _readSession(file, stat.modified));
    } on FileSystemException {
      // Session was deleted mid-scan; skip it.
    }
  }
  sessions.sort((a, b) => b.modified.compareTo(a.modified));
  return sessions.length > limit ? sessions.sublist(0, limit) : sessions;
}

/// Reads a session file the same way pi's own session picker does:
/// display name from the latest `session_info` entry, otherwise the first
/// user message, otherwise the file name.
///
/// ponytail: scans the whole file per session; if listings ever get slow,
/// switch to head/tail reads and a cached index.
Future<PiSession> _readSession(File file, DateTime modified) async {
  String? name;
  String? cwd;
  String? firstUser;

  final lines =
      file.openRead().transform(utf8.decoder).transform(const LineSplitter());
  await for (final line in lines) {
    if (cwd == null && line.startsWith('{"type":"session"')) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map && decoded['cwd'] is String) {
          cwd = decoded['cwd'] as String;
        }
      } on FormatException {
        // Ignore an unreadable header; the listing still works.
      }
      continue;
    }
    if (line.contains('"type":"session_info"')) {
      try {
        final decoded = jsonDecode(line);
        if (decoded is Map && decoded['name'] is String) {
          final value = (decoded['name'] as String).trim();
          if (value.isNotEmpty) name = value;
        }
      } on FormatException {
        // Ignore malformed entries.
      }
      continue;
    }
    if (firstUser == null && line.contains('"role":"user"')) {
      try {
        final decoded = jsonDecode(line);
        final message = decoded is Map ? decoded['message'] : null;
        if (message is Map && message['role'] == 'user') {
          final text = _contentToText(message['content']);
          if (text.trim().isNotEmpty) firstUser = text;
        }
      } on FormatException {
        // Ignore malformed entries.
      }
    }
  }

  final fallback = file.uri.pathSegments.last.replaceAll('.jsonl', '');
  return PiSession(
    path: file.path,
    title: name ?? (firstUser != null ? _snippet(firstUser) : fallback),
    cwd: cwd,
    modified: modified,
  );
}

String _contentToText(Object? content) {
  if (content is String) return content;
  if (content is List) {
    final buffer = StringBuffer();
    for (final block in content) {
      if (block is String) {
        buffer.write(block);
      } else if (block is Map && block['type'] == 'text') {
        buffer.write(block['text'] ?? '');
      }
    }
    return buffer.toString();
  }
  return '';
}

String _snippet(String text) {
  final collapsed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return collapsed.length <= 90 ? collapsed : '${collapsed.substring(0, 90)}…';
}
