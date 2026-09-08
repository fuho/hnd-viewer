import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'constants.dart';
import 'gyro.dart';
import 'video_reassembler.dart';

/// Owns the camera's UDP sessions and exposes the reassembled video and gyro
/// streams.
///
/// Local ports are separated from remote ports so the client can be exercised
/// on loopback; in production both default to the protocol ports.
class CameraClient {
  CameraClient({
    this.host = cameraHost,
    this.broadcast = broadcastHost,
    this.localVideoPort = portVideo,
    this.localGyroPort = portGyro,
    this.remoteVideoPort = portVideo,
    this.remoteGyroPort = portGyro,
  });

  /// Camera address (the AP gateway).
  final String host;

  /// Broadcast address for discovery / wake.
  final String broadcast;

  /// Port this client binds for the video stream.
  final int localVideoPort;

  /// Port this client binds for the gyro stream.
  final int localGyroPort;

  /// Camera port video commands are sent to.
  final int remoteVideoPort;

  /// Camera port gyro commands are sent to.
  final int remoteGyroPort;

  final VideoReassembler _reassembler = VideoReassembler();
  final StreamController<Uint8List> _frames =
      StreamController<Uint8List>.broadcast();
  final StreamController<GyroSample> _gyro =
      StreamController<GyroSample>.broadcast();

  RawDatagramSocket? _videoSocket;
  RawDatagramSocket? _gyroSocket;
  StreamSubscription<RawSocketEvent>? _videoSub;
  StreamSubscription<RawSocketEvent>? _gyroSub;
  Timer? _heartbeat;

  /// Reassembled JPEG frames (one event per complete frame).
  Stream<Uint8List> get frames => _frames.stream;

  /// Accelerometer samples.
  Stream<GyroSample> get gyro => _gyro.stream;

  bool get isRunning => _videoSocket != null;

  /// Bind sockets, wake the camera, and start video + gyro.
  Future<void> start() async {
    _videoSocket =
        await RawDatagramSocket.bind(InternetAddress.anyIPv4, localVideoPort);
    _videoSocket!.broadcastEnabled = true;
    _videoSub = _videoSocket!.listen(_onVideoEvent);

    _gyroSocket =
        await RawDatagramSocket.bind(InternetAddress.anyIPv4, localGyroPort);
    _gyroSub = _gyroSocket!.listen(_onGyroEvent);

    // Wake (broadcast twice), then subscribe and start.
    _videoSocket!.send(wake, InternetAddress(broadcast), portDiscovery);
    _videoSocket!.send(wake, InternetAddress(broadcast), portDiscovery);
    _gyroSocket!.send(gyroSubscribe, InternetAddress(host), remoteGyroPort);
    _videoSocket!.send(startVideo, InternetAddress(host), remoteVideoPort);

    _heartbeat = Timer.periodic(const Duration(seconds: 2), (_) {
      _videoSocket?.send(heartbeat, InternetAddress(host), remoteVideoPort);
    });
  }

  /// One-shot discovery: returns the camera's dev-info JSON, or null on
  /// timeout.
  Future<String?> discover({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final RawDatagramSocket s =
        await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    s.broadcastEnabled = true;
    final Completer<String?> done = Completer<String?>();
    s.listen((event) {
      if (event == RawSocketEvent.read && !done.isCompleted) {
        final Datagram? d = s.receive();
        if (d != null) done.complete(String.fromCharCodes(d.data));
      }
    });
    s.send(wake, InternetAddress(broadcast), portDiscovery);
    s.send(wake, InternetAddress(broadcast), portDiscovery);
    return done.future.timeout(timeout, onTimeout: () {
      s.close();
      return null;
    });
  }

  void _onVideoEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final Datagram? d = _videoSocket?.receive();
    if (d == null || d.data.length < 4) return;
    final Uint8List? jpg = _reassembler.push(d.data);
    if (jpg != null) _frames.add(jpg);
  }

  void _onGyroEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final Datagram? d = _gyroSocket?.receive();
    if (d == null || d.data.length < 20) return;
    _gyro.add(parseGyro(d.data));
  }

  /// Stop streaming and release sockets.
  Future<void> stop() async {
    _heartbeat?.cancel();
    _heartbeat = null;
    await _videoSub?.cancel();
    await _gyroSub?.cancel();
    _videoSub = null;
    _gyroSub = null;
    _videoSocket?.send(stopVideo, InternetAddress(host), remoteVideoPort);
    _videoSocket?.close();
    _gyroSocket?.close();
    _videoSocket = null;
    _gyroSocket = null;
    await _frames.close();
    await _gyro.close();
  }
}
