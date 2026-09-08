/// HND-NE3-D ear-camera stream protocol — pure Dart core.
///
/// See `docs/PROTOCOL.md` for the wire spec. The modules here are UI-free and
/// unit-testable without a device; only [CameraClient] touches the network.
library;

export 'src/protocol/camera_client.dart';
export 'src/protocol/constants.dart';
export 'src/protocol/gyro.dart';
export 'src/protocol/roll_filter.dart';
export 'src/protocol/video_reassembler.dart';
