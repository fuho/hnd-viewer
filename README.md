# hnd-viewer

Cross-platform viewer for the **HND-NE3-D ear camera** (Beken BK7231).
It connects to a factory-sealed unit's Wi-Fi AP and shows the live video
stream plus gyro orientation — no vendor (Chinese, Android-only) companion
app required.

One Flutter codebase targeting **Android, iOS, macOS, Windows, and Linux**.

**Website:** <https://txt.fuho.org/hnd-viewer/> · **Source & releases:**
<https://github.com/fuho/hnd-viewer>

## Why

The factory unit boots its own Wi-Fi AP (`HNDEC_55-xxxxxx`) and streams a
480×480 JPEG video (~12 fps) plus 3-axis accelerometer data over raw UDP
sockets. The vendor app is Android-only and Chinese-language. This project
is a free, open, fully offline-capable replacement viewer.

## What it does

- Discover / connect to the camera AP (gateway `192.168.1.1`)
- Live 480×480 video with rotation, horizontal/vertical mirror, brightness, and smoothing
- Gyro roll overlay with an auto-rotate toggle
- Live sensor chart (accelerometer x/y/z + roll) with a raw readout
- Snapshot to ~/Downloads (desktop) or the gallery (mobile)
- MP4 recording (Record/Stop) saved to ~/Downloads

## Screenshots / demo

Live camera view with the gyro roll overlay:

![hnd-viewer live camera view](media/screenshots/live-view-1.png)

The viewer window and controls:

![hnd-viewer viewer window](media/screenshots/live-view-2.png)

Screen recording of hnd-viewer streaming from the camera:

<video src="media/screenshots/hnd-viewer-demo.mp4" controls width="640"></video>

## The protocol

The camera runs **no HTTP server** — everything is raw UDP on fixed ports.
Browsers cannot open UDP sockets, which is why this is a native app, not a
web page. Full wire spec: [`docs/PROTOCOL.md`](docs/PROTOCOL.md). The
protocol was reverse-engineered and re-implemented from scratch for this
project; it carries no vendor code.

## Status

v1.0.0 released — streaming, snapshot, recording, and the sensor chart are
working on macOS, with builds for Android, Windows, and Linux. iOS pending
signing.

- [x] Standalone repo + 5-platform scaffold (Android/iOS/macOS/Windows/Linux)
- [x] Pure-Dart protocol core (discovery + video reassembly + gyro/roll),
      unit-tested — 27 tests
- [x] Live-view UI (video + gyro roll + rotation/mirror/brightness/smoothing)
- [x] Auto-rotate toggle + live sensor chart (x/y/z + roll)
- [x] Snapshot to ~/Downloads (desktop) / gallery (mobile)
- [x] MP4 recording to ~/Downloads (Record/Stop)
- [x] Automated GitHub Actions releases (Android/Windows/macOS/Linux)
- [ ] iOS build + macOS code signing/notarization

## Running the macOS build

The macOS build is **unsigned and not notarized**, so Gatekeeper blocks it on
first launch. To run it:

1. Download and unzip `hnd-viewer-v0.1.0-macos.app.zip`.
2. **Right-click** `hnd_viewer.app` → **Open** → **Open** (once).

Or via Terminal:

```sh
xattr -cr /path/to/hnd_viewer.app
open /path/to/hnd_viewer.app
```

On first run macOS may also ask to allow **local network** access (to reach the
camera) and **Downloads** (to save snapshots) — accept both.

## Development

Requires the Flutter SDK (stable channel).

```sh
flutter pub get
flutter test              # protocol unit tests (no device needed)
flutter run               # live view on a connected device
flutter build apk --debug # Android debug APK
```

Android builds need a JDK 17 and an Android SDK containing the `android-36`
platform, an NDK, and build-tools. `android/debug.keystore` is committed (the
standard public `androiddebugkey` credential, not a secret) so debug signing
is hermetic. macOS/iOS builds require a full Xcode install.

## License

[MIT](LICENSE)
