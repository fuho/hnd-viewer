import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hnd_viewer/protocol.dart';

Uint8List _frag(int fid, int eof, int pkg, List<int> payload) =>
    Uint8List.fromList([fid, eof, pkg, 0x04, ...payload]);

void main() {
  test('video stream reassembles fragments over loopback UDP', () async {
    // Mock camera on loopback.
    final camera =
        await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    final cameraPort = camera.port;

    final client = CameraClient(
      host: InternetAddress.loopbackIPv4.address,
      broadcast: InternetAddress.loopbackIPv4.address,
      localVideoPort: 0,
      localGyroPort: 0,
      remoteVideoPort: cameraPort,
      remoteGyroPort: cameraPort,
    );

    final jpeg =
        Uint8List.fromList([0xff, 0xd8, 0xde, 0xad, 0xbe, 0xef, 0xff, 0xd9]);

    // When the camera receives the start command, stream one fragmented frame
    // back to the client's source address/port.
    final cameraSub = camera.listen((event) {
      if (event != RawSocketEvent.read) return;
      final Datagram? d = camera.receive();
      if (d == null) return;
      camera.send(_frag(1, 0, 1, jpeg.sublist(0, 3)), d.address, d.port);
      camera.send(_frag(1, 0, 2, jpeg.sublist(3, 6)), d.address, d.port);
      camera.send(_frag(1, 1, 3, jpeg.sublist(6)), d.address, d.port);
    });

    final firstFrame = client.frames.first.timeout(const Duration(seconds: 5));
    await client.start();
    expect(await firstFrame, jpeg);

    await client.stop();
    await cameraSub.cancel();
    camera.close();
  });
}
