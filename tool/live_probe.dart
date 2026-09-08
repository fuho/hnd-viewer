// Live-camera probe: connects the Dart protocol core to a real HND-NE3-D
// camera on its AP and reports what it receives.
//
//   dart run tool/live_probe.dart
import 'dart:async';
import 'dart:io';

import 'package:hnd_viewer/protocol.dart';

Future<void> main() async {
  final client = CameraClient();
  var frames = 0;
  var gyro = 0;
  GyroSample? lastGyro;

  final frameSub = client.frames.listen((jpeg) {
    frames++;
    final ok = jpeg.length >= 2 &&
        jpeg[0] == 0xff &&
        jpeg[1] == 0xd8 &&
        jpeg[jpeg.length - 2] == 0xff &&
        jpeg[jpeg.length - 1] == 0xd9;
    if (frames % 30 == 0) {
      stderr.writeln('  frame #$frames: ${jpeg.length} bytes, '
          '${ok ? 'valid JPEG' : 'BAD JPEG'}');
    }
  });
  final gyroSub = client.gyro.listen((g) {
    gyro++;
    lastGyro = g;
  });

  stderr.writeln('[probe] discovering…');
  final info = await client.discover(timeout: const Duration(seconds: 3));
  stderr.writeln('[probe] devinfo: ${info ?? '(none — skipping discovery)'}');

  stderr.writeln('[probe] starting stream…');
  await client.start();

  final sw = Stopwatch()..start();
  while (sw.elapsed < const Duration(seconds: 12)) {
    await Future<void>.delayed(const Duration(seconds: 1));
    final roll = lastGyro != null
        ? rollFromAxes(lastGyro!.x, lastGyro!.y, lastGyro!.z)
        : null;
    stderr.writeln('  t=${sw.elapsed.inSeconds}s frames=$frames gyro=$gyro '
        'gyro=(${lastGyro?.x},${lastGyro?.y},${lastGyro?.z}) roll=$roll');
  }

  await frameSub.cancel();
  await gyroSub.cancel();
  await client.stop();
  stderr.writeln('[probe] DONE: $frames frames, $gyro gyro samples over '
      '${sw.elapsed.inSeconds}s');
  exit(frames > 0 && gyro > 0 ? 0 : 1);
}
