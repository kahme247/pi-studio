# Pi Studio

A native desktop client for the [Pi coding agent](https://pi.dev) — sessions, transcripts,
worktrees and diffs in one window, entirely on your machine. No Electron: the UI is
Flutter rendering with the GPU, the window chrome is raw Win32, and the agent talks
to `pi --mode rpc` over strict JSONL.

## Features

- **Multi-session, multi-project** — every session owns its own `pi` process, so turns
  keep running while you switch around.
- **Native window** — frameless title bar with Win11 rounded corners, snap, and
  edge-resizing (Win32 FFI), plus native folder/file pickers (no plugins).
- **Git worktrees** — one click creates `~/.pi_studio/worktrees/<repo>/<branch>` and runs
  the session there, so parallel agents never collide.
- **Review rail** — line-numbered diff viewer with per-file counts, a file tree, and a
  command runner; live `+added / -removed` stats in the header.
- **Agent activity feed** — `Processing 2m 20s · 76 token/s` header, one-line steps,
  collapse to the current step, and a `Thought N, Viewed N, Ran N` summary per turn.
- **Sessions sidebar** — grouped by age, searchable, with per-session ⋮ actions
  (rename / archive / delete) and a timeline scrubber to jump between turns.
- **Composer** — model + reasoning picker with search, context-usage ring with token
  and cost breakdowns, `@file` mentions, and access mode pill.

## Layout

```
lib/
  main.dart                     UI: sidebar, transcript, composer, right rail
  pi/pi_client.dart             `pi --mode rpc` client (JSONL framing, commands, events)
  pi/session_store.dart         Session discovery in ~/.pi/agent/sessions
  state/session_controller.dart One session = one pi process + transcript state
  state/projects_store.dart     Persisted project + archive lists
  git/git_ops.dart              Worktrees, branches, diffs (shells out to git)
  platform/folder_picker.dart   Win32 IFileOpenDialog / zenity
  platform/window_controls.dart Win32 drag, resize, minimize/maximize/close
windows/runner/                 Custom frameless window (WM_NCCALCSIZE, hit-testing, DWM)
tool/                           Small diagnostic scripts
```

## Build

Windows (requires Flutter 3.47+ and Visual Studio with the C++ workload):

```powershell
flutter pub get
flutter build windows --release   # -> build\windows\x64\runner\Release\
```

Linux (requires clang, cmake, ninja, pkg-config, libgtk-3-dev):

```bash
flutter build linux --release     # -> build/linux/x64/release/bundle/
```

An Inno Setup script for the Windows installer lives at `installer.iss`.

## Requirements

- The `pi` CLI on `PATH` (`npm install -g @earendil-works/pi-coding-agent`).
- Windows 10/11, or a Linux desktop with GTK 3.
- `git` for worktrees and diffs (optional).
