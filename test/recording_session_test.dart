import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnd_viewer/protocol.dart';
import 'package:hnd_viewer/recording.dart';

void main() {
  test('buffers frames in order with elapsed timestamps', () {
    final s = RecordingSession();
    s.start(const Duration(seconds: 10));
    final f1 = Uint8List.fromList([1, 2, 3]);
    final f2 = Uint8List.fromList([4, 5, 6]);
    s.addFrame(f1, const Duration(seconds: 10));
    s.addFrame(f2, const Duration(seconds: 10, milliseconds: 500));

    expect(s.frameCount, 2);
    expect(s.frames[0].jpeg, f1);
    expect(s.frames[0].elapsed, Duration.zero);
    expect(s.frames[1].elapsed, const Duration(milliseconds: 500));
    expect(s.duration, const Duration(milliseconds: 500));
    expect(s.fps, closeTo(4.0, 0.001)); // 2 frames / 0.5 s
  });

  test('ignores frames before start or while stopped', () {
    final s = RecordingSession();
    s.addFrame(Uint8List.fromList([1]), const Duration(seconds: 1));
    expect(s.frameCount, 0);

    s.start(const Duration(seconds: 5));
    s.addFrame(Uint8List.fromList([1]), const Duration(seconds: 4)); // before
    expect(s.frameCount, 0);
    s.addFrame(Uint8List.fromList([2]), const Duration(seconds: 5));
    expect(s.frameCount, 1);

    s.stop();
    s.addFrame(Uint8List.fromList([3]), const Duration(seconds: 6));
    expect(s.frameCount, 1);
  });

  test('records gyro alongside frames', () {
    final s = RecordingSession();
    s.start(Duration.zero);
    s.addGyro(const GyroSample(1, 2, 3), const Duration(milliseconds: 100));
    expect(s.gyroCount, 1);
    expect(s.gyro[0].elapsed, const Duration(milliseconds: 100));
    expect(s.gyro[0].sample.z, 3);
  });

  test('fps is zero for an empty or zero-duration recording', () {
    final s = RecordingSession();
    expect(s.fps, 0.0);
    s.start(const Duration(seconds: 1));
    expect(s.fps, 0.0);
  });
}
