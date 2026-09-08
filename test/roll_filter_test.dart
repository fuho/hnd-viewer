import 'package:flutter_test/flutter_test.dart';
import 'package:hnd_viewer/protocol.dart';

void main() {
  test('first sample snaps', () {
    final f = RollFilter();
    f.update(42.0);
    expect(f.valid, isTrue);
    expect(f.angle, closeTo(42.0, 1e-9));
  });

  test('deadband suppresses jitter', () {
    final f = RollFilter(alpha: 0.15, deadband: 0.3);
    f.update(0.0);
    f.update(0.2); // within deadband -> no move
    expect(f.angle, closeTo(0.0, 1e-9));
    f.update(1.0); // 1.0 > 0.3 -> 0.15 * 1.0
    expect(f.angle, closeTo(0.15, 1e-9));
  });

  test('wraps the angle difference at ±180', () {
    final f = RollFilter(alpha: 0.5, deadband: 0.0);
    f.update(170.0);
    f.update(-170.0); // diff -340 -> +20 after wrap
    expect(f.angle, closeTo(180.0, 1e-9)); // 170 + 0.5 * 20
  });

  test('null holds last good angle and clears valid', () {
    final f = RollFilter();
    f.update(30.0);
    f.update(null);
    expect(f.valid, isFalse);
    expect(f.angle, closeTo(30.0, 1e-9));
    f.update(40.0); // re-snap after invalid
    expect(f.valid, isTrue);
    expect(f.angle, closeTo(40.0, 1e-9));
  });
}
