import 'dart:io';

/// Thin wrapper over the `git` CLI. No libgit2, no state — the repo on disk
/// is the source of truth.
class GitResult {
  GitResult(this.exitCode, this.stdout, this.stderr);

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get ok => exitCode == 0;

  String get error => stderr.trim().isEmpty ? stdout.trim() : stderr.trim();
}

Future<GitResult> _git(String cwd, List<String> args) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: cwd,
    runInShell: Platform.isWindows,
  );
  return GitResult(result.exitCode, '${result.stdout}', '${result.stderr}');
}

Future<bool> isGitRepo(String dir) async {
  if (!Directory(dir).existsSync()) return false;
  return (await _git(dir, ['rev-parse', '--show-toplevel'])).ok;
}

Future<String?> repoRoot(String dir) async {
  final result = await _git(dir, ['rev-parse', '--show-toplevel']);
  return result.ok ? result.stdout.trim() : null;
}

/// Creates a git worktree for [repoDir] and returns its path and branch.
///
/// Worktrees live outside the repo, under the user profile, so the repo
/// itself stays clean:
///   `~/.pi_studio/worktrees/<repo>/<branch>`
Future<({String path, String branch})> createWorktree(String repoDir) async {
  final root = await repoRoot(repoDir);
  if (root == null) {
    throw StateError('Not a git repository: $repoDir');
  }
  final repoName = root
      .split(RegExp(r'[\\/]'))
      .where((part) => part.isNotEmpty)
      .last;

  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  final branch =
      'pi/${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}${two(now.second)}';

  final home = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      Directory.current.path;
  final worktreePath = [
    home,
    '.pi_studio',
    'worktrees',
    repoName,
    branch.replaceAll('/', '-'),
  ].join(Platform.pathSeparator);

  final result =
      await _git(root, ['worktree', 'add', '-b', branch, worktreePath, 'HEAD']);
  if (!result.ok) {
    throw StateError('git worktree add failed: ${result.error}');
  }
  return (path: worktreePath, branch: branch);
}

Future<String?> currentBranch(String dir) async {
  final result = await _git(dir, ['rev-parse', '--abbrev-ref', 'HEAD']);
  final branch = result.stdout.trim();
  return result.ok && branch.isNotEmpty && branch != 'HEAD' ? branch : null;
}

/// Added/removed line counts of uncommitted changes vs HEAD.
Future<({int additions, int deletions})?> diffStats(String dir) async {
  final result = await _git(dir, ['diff', '--numstat', 'HEAD']);
  if (!result.ok) return null;
  var additions = 0;
  var deletions = 0;
  for (final line in result.stdout.split('\n')) {
    final parts = line.split('\t');
    if (parts.length < 2) continue;
    additions += int.tryParse(parts[0]) ?? 0;
    deletions += int.tryParse(parts[1]) ?? 0;
  }
  return (additions: additions, deletions: deletions);
}

/// A parsed line of a unified diff.
enum DiffLineKind { context, add, remove, hunk, meta }

class DiffLine {
  DiffLine(this.kind, this.text, {this.oldNo, this.newNo});

  final DiffLineKind kind;
  final String text;
  final int? oldNo;
  final int? newNo;
}

List<DiffLine> parseUnifiedDiff(String diff) {
  final lines = <DiffLine>[];
  var oldNo = 0;
  var newNo = 0;
  final raw = diff.trimRight().split('\n');
  for (final line in raw) {
    if (line.startsWith('@@')) {
      final match = RegExp(r'@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@')
          .firstMatch(line);
      if (match != null) {
        oldNo = int.parse(match.group(1)!);
        newNo = int.parse(match.group(2)!);
      }
      lines.add(DiffLine(DiffLineKind.hunk, line));
    } else if (line.startsWith('+++') ||
        line.startsWith('---') ||
        line.startsWith('diff ') ||
        line.startsWith('index ') ||
        line.startsWith('new file') ||
        line.startsWith('deleted file')) {
      lines.add(DiffLine(DiffLineKind.meta, line));
    } else if (line.startsWith('+')) {
      lines.add(DiffLine(DiffLineKind.add, line.substring(1), newNo: newNo++));
    } else if (line.startsWith('-')) {
      lines.add(
        DiffLine(DiffLineKind.remove, line.substring(1), oldNo: oldNo++),
      );
    } else if (line.startsWith(' ') || line.isEmpty) {
      lines.add(
        DiffLine(
          DiffLineKind.context,
          line.isEmpty ? '' : line.substring(1),
          oldNo: oldNo++,
          newNo: newNo++,
        ),
      );
    } else {
      lines.add(DiffLine(DiffLineKind.meta, line));
    }
  }
  return lines;
}

/// Files changed vs HEAD, with status letters (M/A/D/?) and line counts.
Future<List<({String path, String status, int additions, int deletions})>>
    changedFiles(String dir) async {
  final statusResult = await _git(dir, ['status', '--porcelain']);
  if (!statusResult.ok) return const [];

  final numstat = await _git(dir, ['diff', '--numstat', 'HEAD']);
  final counts = <String, (int, int)>{};
  for (final line in numstat.stdout.split('\n')) {
    final parts = line.split('\t');
    if (parts.length < 3) continue;
    final additions = int.tryParse(parts[0]);
    final deletions = int.tryParse(parts[1]);
    if (additions == null || deletions == null) continue;
    counts[parts[2].trim()] = (additions, deletions);
  }

  final files = <({String path, String status, int additions, int deletions})>[];
  for (final line in statusResult.stdout.split('\n')) {
    if (line.trim().length < 3) continue;
    final status = line.substring(0, 2).trim();
    final path = line.substring(3).trim();
    final count = counts[path] ?? (0, 0);
    files.add((
      path: path,
      status: status.isEmpty ? 'M' : status,
      additions: count.$1,
      deletions: count.$2,
    ));
  }
  return files;
}

/// Diff for a single file. Untracked files are rendered as all-additions.
Future<String> fileDiff(String dir, String path) async {
  final tracked = await _git(dir, ['diff', 'HEAD', '--', path]);
  if (tracked.ok && tracked.stdout.trim().isNotEmpty) return tracked.stdout;

  final file = File('$dir/$path');
  try {
    if (!file.existsSync() || await file.length() > 400 * 1024) return '';
    final content = await file.readAsString();
    final lines = content.split('\n');
    final buffer = StringBuffer()
      ..writeln('--- /dev/null')
      ..writeln('+++ b/$path')
      ..writeln('@@ -0,0 +1,${lines.length} @@');
    for (final line in lines) {
      buffer.writeln('+$line');
    }
    return buffer.toString();
  } on FileSystemException {
    return '';
  }
}

Future<List<String>> localBranches(String dir) async {
  final result = await _git(dir, ['branch', '--format=%(refname:short)']);
  if (!result.ok) return const [];
  final branches = result.stdout
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList()
    ..sort();
  return branches;
}

Future<GitResult> checkoutBranch(String dir, String branch) =>
    _git(dir, ['checkout', branch]);

Future<GitResult> createBranch(String dir, String name) =>
    _git(dir, ['checkout', '-b', name]);

/// Uncommitted-change summary of a worktree or repo: status, diff stat, diff.
Future<String> diffHead(String dir) async {
  final status = await _git(dir, ['status', '--short']);
  final stat = await _git(dir, ['diff', 'HEAD', '--stat']);
  final full = await _git(dir, ['diff', 'HEAD']);
  final buffer = StringBuffer();
  if (status.stdout.trim().isNotEmpty) {
    buffer.writeln('# Working tree status');
    buffer.writeln(status.stdout.trim());
    buffer.writeln();
  }
  if (stat.stdout.trim().isNotEmpty) {
    buffer.writeln('# Diff stat');
    buffer.writeln(stat.stdout.trim());
    buffer.writeln();
  }
  if (full.stdout.trim().isNotEmpty) {
    buffer.writeln('# Diff');
    buffer.writeln(full.stdout.trim());
  }
  return buffer.isEmpty ? 'No changes.' : buffer.toString();
}

Future<GitResult> removeWorktree(String repoRootDir, String worktreePath) =>
    _git(repoRootDir, ['worktree', 'remove', '--force', worktreePath]);
