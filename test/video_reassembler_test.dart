import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnd_viewer/protocol.dart';

Uint8List _frag(int fid, int eof, int pkg, List<int> payload) =>
    Uint8List.fromList([fid, eof, pkg, 0x04, ...payload]);

void main() {
  test('reassembles a multi-fragment frame in order', () {
    final r = VideoReassembler();
    final jpeg = Uint8List.fromList(
        [0xff, 0xd8, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff, 0xd9]);
    expect(r.push(_frag(1, 0, 1, jpeg.sublist(0, 3))), isNull);
    expect(r.push(_frag(1, 0, 2, jpeg.sublist(3, 6))), isNull);
    expect(r.push(_frag(1, 1, 3, jpeg.sublist(6))), jpeg);
  });

  test('reassembles out-of-order fragments', () {
    final r = VideoReassembler();
    final jpeg = Uint8List.fromList(
        [0xff, 0xd8, 0x01, 0x02, 0x03, 0x04, 0xff, 0xd9]);
    expect(r.push(_frag(7, 0, 3, jpeg.sublist(4, 6))), isNull);
    expect(r.push(_frag(7, 0, 1, jpeg.sublist(0, 2))), isNull);
    expect(r.push(_frag(7, 1, 4, jpeg.sublist(6))), isNull);
    expect(r.push(_frag(7, 0, 2, jpeg.sublist(2, 4))), jpeg);
  });

  test('trims the camera footer after the EOI marker', () {
    final r = VideoReassembler();
    final jpeg = Uint8List.fromList([0xff, 0xd8, 0x10, 0x20, 0xff, 0xd9]);
    final payload = Uint8List.fromList([...jpeg, 0xde, 0xad, 0xbe, 0xef]);
    expect(r.push(_frag(1, 1, 1, payload)), jpeg);
  });

  test('ignores a short datagram', () {
    final r = VideoReassembler();
    expect(r.push(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('ignores an out-of-range fragment index', () {
    final r = VideoReassembler();
    expect(r.push(_frag(1, 0, 41, [0x01])), isNull);
    expect(r.push(_frag(1, 0, 0, [0x01])), isNull);
  });

  test('deduplicates repeated fragments', () {
    final r = VideoReassembler();
    final jpeg = Uint8List.fromList([0xff, 0xd8, 0xaa, 0xff, 0xd9]);
    expect(r.push(_frag(1, 0, 1, jpeg.sublist(0, 3))), isNull);
    expect(r.push(_frag(1, 0, 1, jpeg.sublist(0, 3))), isNull); // duplicate
    expect(r.push(_frag(1, 1, 2, jpeg.sublist(3))), jpeg);
  });

  test('handles frame id wrap across a reused slot', () {
    final r = VideoReassembler();
    final a = Uint8List.fromList([0xff, 0xd8, 0xa1, 0xff, 0xd9]);
    final b = Uint8List.fromList([0xff, 0xd8, 0xb1, 0xff, 0xd9]);
    expect(r.push(_frag(255, 1, 1, a)), a);
    // 255 % 3 == 0 and 0 % 3 == 0: the new fid must reset the slot.
    expect(r.push(_frag(0, 1, 1, b)), b);
  });

  test('reassembles a large multi-fragment frame byte-identically', () {
    final r = VideoReassembler();
    // ~30 KB payload split across many fragments, with a trailing footer
    // (the camera appends a short footer after the JPEG EOI marker).
    final body = Uint8List.fromList(
        List<int>.generate(30 * 1024, (i) => (i * 31) & 0xff));
    final jpeg = Uint8List.fromList([0xff, 0xd8, ...body, 0xff, 0xd9]);
    final payload = Uint8List.fromList([...jpeg, 0xde, 0xad, 0xbe, 0xef]);

    const fragSize = 1000;
    final n = (payload.length + fragSize - 1) ~/ fragSize;
    expect(n, lessThanOrEqualTo(40));

    Uint8List? out;
    for (var i = 0; i < n; i++) {
      final start = i * fragSize;
      final end = (start + fragSize) > payload.length
          ? payload.length
          : start + fragSize;
      out = r.push(_frag(42, i == n - 1 ? 1 : 0, i + 1,
          payload.sublist(start, end)));
    }
    expect(out, jpeg);
  });
}
