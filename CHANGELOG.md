# Changelog

All notable changes to this project are documented in this file. The format is
based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-09-09

### Added

- Live 480×480 video from the HND-NE3 ear camera over raw UDP.
- Gyro roll overlay with an auto-rotate toggle.
- Live sensor chart (accelerometer x/y/z + roll) with a raw readout.
- Snapshot to ~/Downloads on desktop, or the gallery on mobile.
- MP4 recording (Record/Stop) saved to ~/Downloads via FFmpeg.
- Horizontal/vertical mirror, brightness, smoothing, and extra-rotation controls.
- GitHub Actions CI (analyze + test), release builds, and a GitHub Pages website.

### Platforms

- Android, Windows, macOS, and Linux (macOS/Windows unsigned). iOS pending
  Apple signing.

### Known issues

- macOS and Windows builds are unsigned — see the README for how to run them.
