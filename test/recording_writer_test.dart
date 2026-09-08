import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnd_viewer/recording.dart';

void main() {
  test('JpegSequenceWriter writes frames and a manifest', () async {
    final dir = Directory.systemTemp.createTempSync('hnd_rec');
    addTearDown(() => dir.deleteSync(recursive: true));

    final w = JpegSequenceWriter(Directory('${dir.path}/rec'));
    await w.start();
    await w.writeFrame(Uint8List.fromList([1, 2, 3]), Duration.zero);
    await w.writeFrame(
        Uint8List.fromList([4, 5, 6]), const Duration(milliseconds: 100));
    final path = await w.finish();

    expect(path, '${dir.path}/rec');
    expect(File('$path/000000.jpg').existsSync(), isTrue);
    expect(File('$path/000001.jpg').existsSync(), isTrue);
    final manifest = File('$path/manifest.json').readAsStringSync();
    expect(manifest, contains('"frameCount": 2'));
    expect(manifest, contains('"durationMs": 100'));
  });

  test('JpegSequenceWriter.start clears a previous recording', () async {
    final dir = Directory.systemTemp.createTempSync('hnd_rec2');
    addTearDown(() => dir.deleteSync(recursive: true));

    final w = JpegSequenceWriter(Directory('${dir.path}/rec'));
    await w.start();
    await w.writeFrame(Uint8List.fromList([1]), Duration.zero);
    await w.start(); // reset
    await w.writeFrame(Uint8List.fromList([2]), Duration.zero);
    await w.finish();
    expect(File('${dir.path}/rec/000000.jpg').existsSync(), isTrue);
    expect(File('${dir.path}/rec/000001.jpg').existsSync(), isFalse);
  });
}
