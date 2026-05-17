# CUE

CUE (C-U-E) is a cross-platform Flutter app for earphone-triggered audio
sessions, daily searchable transcripts, and catchphrase-based habit tracking.

## Highlights

- Starts in light mode by default with CUE's off-white `#F8F9FC` surface and
  blue `#0066FF` accent.
- Riverpod-powered app state and Drift-backed local persistence.
- Automatic recording sessions when wired or Bluetooth earphones connect.
- Persistent foreground recording notification on Android and iOS background
  mode registration.
- Daily continuous transcript with search and inline editing.
- Catchphrases with polarity, highlight color, notes, location capture, mood
  selection, and transcript highlighting.

## Local setup

This repository expects a Flutter SDK with Dart 3.9+.

```sh
flutter pub get
flutter run
```

The native earphone route listeners are implemented in Android Kotlin and iOS
Swift. Run on a physical device for the full recording, Bluetooth, microphone,
and location behavior.

## iOS signing

To sign CUE with your Apple Developer account and install it on your iPhone,
see [docs/ios-signing.md](docs/ios-signing.md).
