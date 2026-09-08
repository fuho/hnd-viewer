import 'dart:math' as math;
import 'dart:typed_data';

/// One accelerometer sample from the camera's 24-byte gyro datagram.
class GyroSample {
  const GyroSample(
    this.x,
    this.y,
    this.z, {
    this.mid = const <int>[],
    this.tail = 0,
  });

  /// Accelerometer X (int16, big-endian, bytes 0..1).
  final int x;

  /// Accelerometer Y (int16, big-endian, bytes 2..3).
  final int y;

  /// Accelerometer Z (int16, big-endian, bytes 4..5).
  final int z;

  /// Unknown 12 bytes (bytes 6..17).
  final List<int> mid;

  /// Unknown uint16 (bytes 18..19).
  final int tail;

  @override
  String toString() => 'GyroSample(x: $x, y: $y, z: $z)';
}

/// Parses a 24-byte gyro datagram. [packet] must be at least 20 bytes.
GyroSample parseGyro(Uint8List packet) {
  final ByteData data = ByteData.sublistView(packet);
  return GyroSample(
    data.getInt16(0, Endian.big),
    data.getInt16(2, Endian.big),
    data.getInt16(4, Endian.big),
    mid: packet.sublist(6, 18),
    tail: data.getUint16(18, Endian.big),
  );
}

/// Roll angle in degrees derived from two accelerometer axes.
///
/// [axisPair] `yz` uses (y, z) and `zy` uses (z, y). Returns null when the
/// magnitude of the two axes is below [threshold] — the device is
/// near-vertical, so roll is undefined.
double? rollFromAxes(
  int x,
  int y,
  int z, {
  String axisPair = 'yz',
  bool invert = false,
  double threshold = 1500.0,
}) {
  final int a = axisPair == 'yz' ? y : z;
  final int b = axisPair == 'yz' ? z : y;
  final double mag = math.sqrt((a * a + b * b).toDouble());
  if (mag < threshold) return null;
  final double ang = math.atan2(a.toDouble(), b.toDouble()) * 180 / math.pi;
  return invert ? -ang : ang;
}
