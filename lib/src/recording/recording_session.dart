import 'dart:typed_data';

import 'package:hnd_viewer/src/protocol/gyro.dart';

/// A video frame captured during a recording.
class RecordedFrame {
  const RecordedFrame(this.elapsed, this.jpeg);

  /// Time since the recording started.
  final Duration elapsed;

  /// JPEG frame bytes.
  final Uint8List jpeg;
}

/// A gyro sample captured during a recording.
class RecordedGyro {
  const RecordedGyro(this.elapsed, this.sample);

  /// Time since the recording started.
  final Duration elapsed;

  /// The accelerometer sample.
  final GyroSample sample;
}

/// Accumulates a recording: ordered video frames and gyro samples, with
/// duration and fps accounting. Encoding is a separate concern
/// (`RecordingWriter`).
class RecordingSession {
  final List<RecordedFrame> frames = [];
  final List<RecordedGyro> gyro = [];

  Duration? _start;
  Duration _lastFrame = Duration.zero;
  bool _recording = false;

  bool get isRecording => _recording;
  int get frameCount => frames.length;
  int get gyroCount => gyro.length;

  /// Time of the last frame relative to the recording start.
  Duration get duration => _lastFrame;

  /// Frames per second over the whole recording.
  double get fps => duration.inMilliseconds > 0
      ? frames.length * 1000.0 / duration.inMilliseconds
      : 0.0;

  /// Begin a new recording, resetting any previous data.
  void start(Duration now) {
    _start = now;
    _lastFrame = Duration.zero;
    frames.clear();
    gyro.clear();
    _recording = true;
  }

  /// Add a JPEG frame captured at [now] (monotonic clock time).
  void addFrame(Uint8List jpeg, Duration now) {
    final Duration? elapsed = _elapsed(now);
    if (elapsed == null) return;
    _lastFrame = elapsed;
    frames.add(RecordedFrame(elapsed, jpeg));
  }

  /// Add a gyro sample captured at [now] (monotonic clock time).
  void addGyro(GyroSample sample, Duration now) {
    final Duration? elapsed = _elapsed(now);
    if (elapsed == null) return;
    gyro.add(RecordedGyro(elapsed, sample));
  }

  void stop() {
    _recording = false;
  }

  Duration? _elapsed(Duration now) {
    if (!_recording || _start == null) return null;
    final Duration elapsed = now - _start!;
    if (elapsed.isNegative) return null;
    return elapsed;
  }
}
