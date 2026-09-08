# HANDOFF — hnd-viewer

Cross-platform viewer for the **HND-NE3-D ear camera** (factory-sealed unit).
This is a **standalone project** — its own git repo — that branched off the
main HND ear-cam firmware work. Everything below lives in this repo only;
the firmware repo is untouched apart from one `.gitignore` line pointing at
`hnd-viewer/`.

## One-line status

The app **connects to a factory-sealed camera and shows live video + gyro**.
Android builds and runs on-device; the protocol core is fully validated
against a real unit. Remaining: MP4 recording (FFmpeg), packaging, iOS/macOS
(a full Xcode install), and end-to-end testing of the *app* on the Pixel.

## What this is

The factory unit boots a Wi-Fi AP (`HNDEC_55-xxxxxx`, gateway `192.168.1.1`)
and streams 480×480 JPEG (~12 fps) + accelerometer over **raw UDP** — no HTTP,
so a browser cannot reach it. This Flutter app replaces the vendor's
Android-only Chinese companion app with an open, offline viewer targeting
**Android, iOS, macOS, Windows, Linux** from one codebase.

Wire protocol: [`docs/PROTOCOL.md`](docs/PROTOCOL.md). Summary:

| Purpose | Bytes | Addr |
|---|---|---|
| discovery/wake | `66 30 01 01` | broadcast `192.168.1.255:46526` |
| start video | `20 36` (`" 6"`) | `192.168.1.1:44506` |
| gyro subscribe | `86 06 01` | `192.168.1.1:52219` |

Video datagrams are `[fid][eof][pkg][0x04] + JPEG fragment`, reassembled over
3 rotating buffers × 40 slots (`fid % 3`); the EOI `FF D9` footer is trimmed.
Gyro packets are 24 bytes: 3× int16 BE (X,Y,Z) at bytes 0..5, roll derived
from `atan2(y,z)`.

## Done (verified)

- **M0** standalone repo; **M1** 5-platform Flutter scaffold (Flutter 3.47.2).
- **M2** pure-Dart protocol core: `CameraClient`, `VideoReassembler`,
  `parseGyro`, `rollFromAxes`, `RollFilter`. 23/23 tests, `flutter analyze`
  clean, incl. a loopback UDP integration test and a 30 KB multi-fragment
  reassembly test.
- **M3** live-view UI: video + gyro roll + rotation/mirror/brightness/
  smoothing, `ViewerPage` (`lib/src/viewer_page.dart`).
- **M4** snapshot to photo gallery via `gal` (Snapshot button).
- **M5 core** `RecordingSession` (frames + gyro with elapsed timestamps, fps)
  + `RecordingWriter` interface + a portable `JpegSequenceWriter` fallback.
- **Android build** works: `flutter build apk --debug`; APK installs and
  launches on a **Pixel 9 (Android 17)** with no crashes.
- **Live validation** (this session): `tool/live_probe.dart` against the
  factory unit — 130 valid JPEG frames + 141 gyro samples in 12 s (~10.8 fps,
  ~8.8 KB/frame). Discovery returned full dev-info:

  ```json
  { "model": "EAR_CAMERA", "brand": "HND-NE3", "soc": "BK7231UQFN40",
    "firmware": "1.0.0", "macid": "FC584A5130F2", "imu_axis": "3",
    "calibrated": "0", "wifi_mode": "AP" }
  ```

### Bug fixed this session
`CameraClient.discover()` leaked its ephemeral UDP socket (only closed on the
timeout path), which hung a subsequent `start()`. Fixed with a `finally`.
Hardware testing caught this — the loopback unit test did not.

## Build / run (this workspace)

The toolchain is vendored *inside* the repo to stay within the sandbox:

- Flutter SDK: `.flutter/` (3.47.2); per-user state redirected to
  `.flutter-user/` via `HOME="$PWD/.flutter-user"`.
- Android SDK overlay: `.android-sdk/` (symlinks the real SDK at
  `~/Library/Android/sdk`, plus a downloaded `platforms;android-36`).
- Gradle cache: `.gradle/` (`GRADLE_USER_HOME`). JDK: Homebrew `openjdk@17`.

```sh
export HOME="$PWD/.flutter-user" FLUTTER_SUPPRESS_ANALYTICS=true
.flutter/bin/flutter test                      # unit tests (no device)
.flutter/bin/flutter build apk --debug         # Android APK
.flutter/bin/dart run tool/live_probe.dart     # live camera (Mac on AP)
```

Android APK build (full env):
```sh
export ANDROID_HOME="$PWD/.android-sdk" ANDROID_SDK_ROOT="$PWD/.android-sdk" \
       JAVA_HOME=/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home \
       GRADLE_USER_HOME="$PWD/.gradle" HOME="$PWD/.flutter-user" \
       FLUTTER_SUPPRESS_ANALYTICS=true
.flutter/bin/flutter build apk --debug
```

`android/app/build.gradle.kts` pins `ndkVersion`/`buildToolsVersion` to what
this machine has (30.0 / 37.0) and uses a committed `android/debug.keystore`
for hermetic debug signing — both can be reverted to Flutter defaults on a
machine with the full SDK.

## Remaining

1. **M5 (finish): FFmpeg MP4 writer** — implement `RecordingWriter` (encode
   JPEG frames → H.264 → MP4). `ffmpeg` is on this Mac; pick a Flutter FFmpeg
   plugin (or platform encoders) and wire it behind the existing interface.
2. **M6 packaging** — release builds + signing + installers for all five
   targets.
3. **iOS/macOS** — need a full Xcode install (`xcode-select` currently points
   at CommandLineTools; no `xcodebuild`).
4. **App on the Pixel** — connect the Pixel to the camera AP and drive the
   actual UI (the Mac-side probe already proves the protocol; the app UI is
   smoke-tested but not yet shown live video on-device).
5. **Gyro roll calibration** — default `axisPair:'yz'`/no-invert reads ≈ −174°
   for a flat camera (near the ±180 wrap). Expose an invert/axis toggle or
   calibrate.

## Key files

- `lib/protocol.dart` + `lib/src/protocol/` — protocol core (no UI).
- `lib/recording.dart` + `lib/src/recording/` — recording session/writer.
- `lib/src/viewer_page.dart` — the app UI.
- `tool/live_probe.dart` — headless live-camera test.
- `test/` — unit + integration tests.
- `docs/PROTOCOL.md` — wire spec.
