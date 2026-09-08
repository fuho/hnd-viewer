import 'dart:typed_data';

/// Wire constants for the HND-NE3-D ear-camera stream protocol.
///
/// See `docs/PROTOCOL.md`. All integers are big-endian on the wire.
const String cameraHost = '192.168.1.1';

/// Broadcast address used for discovery / wake.
const String broadcastHost = '192.168.1.255';

/// UDP ports.
const int portDiscovery = 46526;
const int portVideo = 44506;
const int portGyro = 52219;

/// Discovery / wake datagram.
final Uint8List wake = Uint8List.fromList([0x66, 0x30, 0x01, 0x01]);

/// Start the video stream (ASCII `" 6"`).
final Uint8List startVideo = Uint8List.fromList([0x20, 0x36]);

/// Stop the video stream (ASCII `" 7"`).
final Uint8List stopVideo = Uint8List.fromList([0x20, 0x37]);

/// Heartbeat (ASCII `" 5"`), sent roughly every 2 s to keep the session alive.
final Uint8List heartbeat = Uint8List.fromList([0x20, 0x35]);

/// Subscribe to the accelerometer stream.
final Uint8List gyroSubscribe = Uint8List.fromList([0x86, 0x06, 0x01]);

/// JPEG end-of-image marker (`FF D9`); the camera appends a short footer after
/// it that must be trimmed.
const int jpegEoiHi = 0xff;
const int jpegEoiLo = 0xd9;
