# hnd-viewer

Cross-platform viewer for the **HND-NE3-D ear camera** (Beken BK7252N).
It connects to a factory-sealed unit's Wi-Fi AP and shows the live video
stream plus gyro orientation — no vendor (Chinese, Android-only) companion
app required.

One Flutter codebase targeting **Android, iOS, macOS, Windows, and Linux**.

## Why

The factory unit boots its own Wi-Fi AP (`HNDEC_55-xxxxxx`) and streams a
480×480 JPEG video (~12 fps) plus 3-axis accelerometer data over raw UDP
sockets. The vendor app is Android-only and Chinese-language. This project
is a free, open, fully offline-capable replacement viewer.

## What it does

- Discover / connect to the camera AP (gateway `192.168.1.1`)
- Live 480×480 video with rotation, mirror, and brightness
- Gyro roll overlay (the ear camera's orientation)
- Snapshot to gallery
- MP4 recording (planned)

## The protocol

The camera runs **no HTTP server** — everything is raw UDP on fixed ports.
Browsers cannot open UDP sockets, which is why this is a native app, not a
web page. Full wire spec: [`docs/PROTOCOL.md`](docs/PROTOCOL.md). The
protocol was reverse-engineered and re-implemented from scratch for this
project; it carries no vendor code.

## Status

In progress.

- [x] Standalone repo + 5-platform scaffold (Android/iOS/macOS/Windows/Linux)
- [x] Pure-Dart protocol core (discovery + video reassembly + gyro/roll),
      unit-tested — 16 tests, including a loopback UDP integration test
- [x] Live-view UI (video + gyro roll + rotation/mirror/brightness/smoothing)
- [ ] Snapshot to gallery
- [ ] MP4 recording
- [ ] Packaging / installers for all five targets

## Development

Requires the Flutter SDK (stable channel).

```sh
flutter pub get
flutter test              # protocol unit tests (no device needed)
flutter run               # live view on a connected device
```

## License

To be chosen.
