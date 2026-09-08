import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnd_viewer/recording.dart';

/// Number of JPEG frames used by the tests.
const int _frameCount = 8;

/// Generates [_frameCount] distinct valid JPEG frames (480x480) by asking
/// ffmpeg to render its `testsrc2` test pattern into [directory]. Returns the
/// frames in order as byte arrays.
Future<List<Uint8List>> _generateJpegFrames(
    String ffmpeg, String directory) async {
  final ProcessResult result = await Process.run(ffmpeg, <String>[
    '-v', 'error',
    '-y',
    '-f', 'lavfi',
    '-i', 'testsrc2=size=480x480:rate=25',
    '-frames:v', '$_frameCount',
    '-c:v', 'mjpeg',
    '-q:v', '3',
    '$directory${Platform.pathSeparator}f_%02d.jpg',
  ]);
  expect(result.exitCode, 0, reason: 'frame generation failed: ${result.stderr}');

  final List<Uint8List> frames = <Uint8List>[];
  for (int i = 1; i <= _frameCount; i++) {
    final String name = i.toString().padLeft(2, '0');
    frames.add(await File('$directory/f_$name.jpg').readAsBytes());
  }
  return frames;
}

/// Runs `ffprobe -v error ... <file>` and returns its stdout.
Future<String> _probe(String ffprobe, String file, List<String> extra) async {
  final ProcessResult result = await Process.run(ffprobe, <String>[
    '-v', 'error',
    '-select_streams', 'v:0',
    '-show_entries', 'stream=codec_name,width,height,nb_frames',
    '-show_entries', 'format=duration',
    '-of', 'default=noprint_wrappers=1',
    ...extra,
    file,
  ]);
  expect(result.exitCode, 0, reason: 'ffprobe failed: ${result.stderr}');
  return result.stdout as String;
}

void main() {
  test('transcodes JPEG frames to an MP4 with the expected frame count and '
      'duration', () async {
    final String? ffmpeg = await findExecutableOnPath('ffmpeg');
    final String? ffprobe = await findExecutableOnPath('ffprobe');
    if (ffmpeg == null || ffprobe == null) {
      // ignore: avoid_print
      print('ffmpeg/ffprobe not found on PATH; skipping FfmpegMp4Writer tests');
      return;
    }

    final Directory tmp = Directory.systemTemp.createTempSync('hnd_ffmpeg_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final List<Uint8List> frames = await _generateJpegFrames(ffmpeg, tmp.path);
    // testsrc2 keeps moving, so every generated frame should differ.
    expect(frames.length, _frameCount);
    expect(frames[0].length, greaterThan(1000));
    expect(frames[0], isNot(equals(frames[1])));

    // Deliberately uneven frame intervals, ending at 600 ms.
    final List<Duration> elapsed = <Duration>[
      Duration.zero,
      const Duration(milliseconds: 71),
      const Duration(milliseconds: 140),
      const Duration(milliseconds: 210),
      const Duration(milliseconds: 300),
      const Duration(milliseconds: 380),
      const Duration(milliseconds: 500),
      const Duration(milliseconds: 600),
    ];

    final File out = File('${tmp.path}${Platform.pathSeparator}rec.mp4');
    final FfmpegMp4Writer writer = FfmpegMp4Writer(
      outputPath: out.path,
      ffmpegPath: ffmpeg,
    );
    await writer.start();
    for (int i = 0; i < frames.length; i++) {
      await writer.writeFrame(frames[i], elapsed[i]);
    }
    final String path = await writer.finish();

    expect(path, out.absolute.path);
    final File produced = File(path);
    expect(produced.existsSync(), isTrue);
    expect(produced.lengthSync(), greaterThan(5000),
        reason: 'the MP4 should be non-trivial in size');

    final String probe = await _probe(ffprobe, path, <String>[]);
    expect(probe, contains('codec_name=h264'));
    expect(probe, contains('width=480'));
    expect(probe, contains('height=480'));
    expect(probe, contains('nb_frames=$_frameCount'));

    // Container duration should track the final frame's elapsed time (600 ms).
    final double? duration = double.tryParse(
        RegExp(r'^duration=([0-9.]+)$', multiLine: true).firstMatch(probe)!.group(1)!);
    expect(duration, isNotNull);
    expect(duration!, closeTo(0.6, 0.05));
  });

  test('falls back to the nominal fps when elapsed carries no timing',
      () async {
    final String? ffmpeg = await findExecutableOnPath('ffmpeg');
    final String? ffprobe = await findExecutableOnPath('ffprobe');
    if (ffmpeg == null || ffprobe == null) {
      // ignore: avoid_print
      print('ffmpeg/ffprobe not found on PATH; skipping FfmpegMp4Writer tests');
      return;
    }

    final Directory tmp = Directory.systemTemp.createTempSync('hnd_ffmpeg2_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final List<Uint8List> frames = await _generateJpegFrames(ffmpeg, tmp.path);
    final File out = File('${tmp.path}${Platform.pathSeparator}rec.mp4');
    final FfmpegMp4Writer writer = FfmpegMp4Writer(
      outputPath: out.path,
      ffmpegPath: ffmpeg,
      nominalFps: 10.0,
    );
    await writer.start();
    for (int i = 0; i < frames.length; i++) {
      await writer.writeFrame(frames[i], Duration.zero);
    }
    final String path = await writer.finish();

    final String probe = await _probe(ffprobe, path, <String>[]);
    expect(probe, contains('nb_frames=$_frameCount'));
    // 8 frames at the nominal 10 fps => ~0.8 s container duration.
    final double? duration = double.tryParse(
        RegExp(r'^duration=([0-9.]+)$', multiLine: true).firstMatch(probe)!.group(1)!);
    expect(duration, isNotNull);
    expect(duration!, closeTo(0.8, 0.05));
  });

  test('start overwrites a previous file and finish fails loudly on a bad '
      'ffmpeg path', () async {
    final String? ffmpeg = await findExecutableOnPath('ffmpeg');
    if (ffmpeg == null) {
      // ignore: avoid_print
      print('ffmpeg not found on PATH; skipping FfmpegMp4Writer tests');
      return;
    }

    final Directory tmp = Directory.systemTemp.createTempSync('hnd_ffmpeg3_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final List<Uint8List> frames = await _generateJpegFrames(ffmpeg, tmp.path);

    // Overwrite: plant a stale file at the output path first.
    final File out = File('${tmp.path}${Platform.pathSeparator}rec.mp4');
    await out.writeAsBytes(Uint8List.fromList(<int>[1, 2, 3, 4, 5]));

    final FfmpegMp4Writer writer = FfmpegMp4Writer(
      outputPath: out.path,
      ffmpegPath: ffmpeg,
    );
    await writer.start();
    await writer.writeFrame(frames[0], Duration.zero);
    await writer.writeFrame(frames[1], const Duration(milliseconds: 100));
    final String path = await writer.finish();
    expect(path, out.absolute.path);
    final int size = File(path).lengthSync();
    expect(size, greaterThan(1000)); // replaced, not the planted 5 bytes.

    // Failure: an explicit ffmpeg path that does not exist must throw a
    // descriptive error from finish() and leave no output file behind.
    final FfmpegMp4Writer broken = FfmpegMp4Writer(
      outputPath: '${tmp.path}${Platform.pathSeparator}broken.mp4',
      ffmpegPath: '${tmp.path}${Platform.pathSeparator}does_not_exist',
    );
    await broken.start();
    await broken.writeFrame(frames[0], Duration.zero);
    await expectLater(
        broken.finish(), throwsA(isA<FileSystemException>()));
    expect(File('${tmp.path}${Platform.pathSeparator}broken.mp4').existsSync(),
        isFalse);
  });

  test('finish throws a descriptive error when ffmpeg cannot decode the '
      'input', () async {
    final String? ffmpeg = await findExecutableOnPath('ffmpeg');
    if (ffmpeg == null) {
      // ignore: avoid_print
      print('ffmpeg not found on PATH; skipping FfmpegMp4Writer tests');
      return;
    }

    final Directory tmp = Directory.systemTemp.createTempSync('hnd_ffmpeg4_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final File out = File('${tmp.path}${Platform.pathSeparator}bad.mp4');
    final FfmpegMp4Writer writer = FfmpegMp4Writer(
      outputPath: out.path,
      ffmpegPath: ffmpeg,
    );
    await writer.start();
    // Not a JPEG at all: ffmpeg's mjpeg demuxer must fail with a non-zero exit.
    await writer.writeFrame(
        Uint8List.fromList(<int>[1, 2, 3, 4, 5]), Duration.zero);
    await writer.writeFrame(
        Uint8List.fromList(<int>[6, 7, 8, 9, 10]), const Duration(milliseconds: 50));

    await expectLater(
        writer.finish(), throwsA(isA<ProcessException>()));
    expect(File(out.absolute.path).existsSync(), isFalse,
        reason: 'no partial file should remain after a failed finish');
  });
}
