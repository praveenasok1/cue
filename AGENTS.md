# AGENTS.md

## Cursor Cloud specific instructions

### Overview

CUE is a cross-platform Flutter mobile app (earphone-triggered habit transcription journal). It uses Riverpod for state management and Drift (SQLite) for local persistence. All code lives on the `cursor/build-cue-flutter-app-167c` branch — the `main` branch only has a bare README.

### Prerequisites

- **Flutter SDK** installed at `/opt/flutter_sdk/flutter` (Dart 3.9+ required by `pubspec.yaml`).
- PATH must include `/opt/flutter_sdk/flutter/bin`.
- **Linux desktop build deps**: `ninja-build`, `libgtk-3-dev`, `lld`, `llvm-18`, `libstdc++-14-dev`.

### Common commands

| Task | Command |
|------|---------|
| Install deps | `flutter pub get` |
| Lint/analyze | `flutter analyze` |
| Run tests | `flutter test` |
| Build Linux | `flutter build linux` |
| Run (Linux) | `flutter run -d linux` |
| Build web | `flutter build web` |

### Gotchas for Cloud VMs

- **Web target does not work**: `flutter_foreground_task` calls `dart:isolate` which is unsupported on `dart4web`. The app crashes at startup on Chrome. Use the **Linux desktop** target instead.
- **`MissingPlatformDirectoryException`**: The Drift database and path_provider throw this on Linux desktop because the `flutter create --platforms=linux` scaffold was added after the fact. The app UI still renders and is interactive; only DB persistence fails.
- **`MissingPluginException` on `cue/audio_route_events`**: The native earphone route listener (Kotlin/Swift) has no Linux desktop implementation. Audio route detection won't function on Linux.
- **libEGL warnings**: `DRI3 error: Could not get DRI3 device` is expected in headless/VM environments without GPU acceleration. The app renders via software fallback.
- **Hot reload/restart**: `flutter run -d linux` supports `r` (hot reload) and `R` (hot restart) from the terminal.
