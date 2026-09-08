import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Writes a recording to persistent storage.
///
/// The production MP4 writer will implement this with FFmpeg; the included
/// [JpegSequenceWriter] is a portable, dependency-free fallback.
abstract class RecordingWriter {
  /// Open the output and prepare to receive frames.
  Future<void> start();

  /// Write one JPEG frame captured at [elapsed] since recording start.
  Future<void> writeFrame(Uint8List jpeg, Duration elapsed);

  /// Finalize and return a path to the recorded artifact.
  Future<String> finish();
}

/// A dependency-free writer that dumps frames as numbered JPEG files plus a
/// `manifest.json`. Used as a fallback and for tests.
class JpegSequenceWriter implements RecordingWriter {
  JpegSequenceWriter(this.outputDirectory);

  final Directory outputDirectory;
  int _index = 0;
  final List<Map<String, Object?>> _entries = [];
  Duration _last = Duration.zero;

  @override
  Future<void> start() async {
    if (await outputDirectory.exists()) {
      await outputDirectory.delete(recursive: true);
    }
    await outputDirectory.create(recursive: true);
    _index = 0;
    _entries.clear();
    _last = Duration.zero;
  }

  @override
  Future<void> writeFrame(Uint8List jpeg, Duration elapsed) async {
    final String name = _index.toString().padLeft(6, '0');
    await File('${outputDirectory.path}/$name.jpg')
        .writeAsBytes(jpeg, flush: true);
    _entries.add({'index': _index, 'ms': elapsed.inMilliseconds});
    _last = elapsed;
    _index++;
  }

  @override
  Future<String> finish() async {
    final double fps = _last.inMilliseconds > 0
        ? _index * 1000.0 / _last.inMilliseconds
        : 0.0;
    final Map<String, Object?> manifest = {
      'format': 'jpeg-sequence',
      'frameCount': _index,
      'durationMs': _last.inMilliseconds,
      'fps': fps,
      'entries': _entries,
    };
    await File('${outputDirectory.path}/manifest.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(manifest));
    return outputDirectory.path;
  }
}
