import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnd_viewer/protocol.dart';

void main() {
  test('parses a 24-byte gyro datagram', () {
    final pkt = Uint8List.fromList([
      0x01, 0x02, 0xff, 0xfe, 0x00, 0x04, // x=258, y=-2, z=4
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, // mid (12 bytes)
      0xab, 0xcd, // tail = 0xabcd
    ]);
    final g = parseGyro(pkt);
    expect(g.x, 258);
    expect(g.y, -2);
    expect(g.z, 4);
    expect(g.tail, 0xabcd);
    expect(g.mid.length, 12);
  });

  test('roll from axes: yz pair', () {
    // Pure +z => atan2(y=0, z=+1) = 0 deg.
    expect(rollFromAxes(0, 0, 2000), closeTo(0, 0.001));
    // +y => atan2(y=2000, z=0) = 90 deg.
    expect(rollFromAxes(0, 2000, 0), closeTo(90, 0.001));
    // Near-vertical (small magnitude) => undefined.
    expect(rollFromAxes(0, 0, 500), isNull);
    expect(rollFromAxes(0, 0, 0), isNull);
  });

  test('roll invert and axis pair', () {
    expect(rollFromAxes(0, 2000, 0, invert: true), closeTo(-90, 0.001));
    expect(rollFromAxes(0, 2000, 0, axisPair: 'zy'), closeTo(0, 0.001));
  });
}
