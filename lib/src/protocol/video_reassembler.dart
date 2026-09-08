import 'dart:typed_data';

import 'constants.dart';

/// Reassembles the camera's fragmented JPEG video stream.
///
/// The vendor decoder keeps three rotating frame buffers (40 slots each); the
/// active slot is `frameId % 3`. A new frame id resets its slot. The fragment
/// carrying `eof = 1` announces the total fragment count in its index, and a
/// frame is complete once the slot holds every fragment `1..total`.
///
/// Datagram layout (see `docs/PROTOCOL.md`):
///
/// ```text
/// byte 0  fid   frame id
/// byte 1  eof   end-of-frame flag (1 on the last fragment)
/// byte 2  pkg   1-based fragment index (1..40)
/// byte 3  0x04  constant
/// byte 4+ …     JPEG fragment payload
/// ```
class VideoReassembler {
  static const int _maxFragments = 40;
  static const int _frameBuffers = 3;
  static const int _headerLen = 4;

  final List<List<Uint8List?>> _buf = List.generate(
      _frameBuffers, (_) => List<Uint8List?>.filled(_maxFragments, null));
  final List<int> _count = List.filled(_frameBuffers, 0);
  final List<int> _total = List.filled(_frameBuffers, 0);
  final List<int> _lastFid = List.filled(_frameBuffers, -1);

  /// Feed one UDP datagram.
  ///
  /// Returns a complete JPEG frame once the frame finishes reassembling,
  /// otherwise null (still incomplete, or a malformed datagram).
  Uint8List? push(Uint8List datagram) {
    if (datagram.length < _headerLen) return null;

    final int fid = datagram[0];
    final int eof = datagram[1];
    final int pkg = datagram[2] - 1; // 1-based on the wire -> 0-based index
    // datagram[3] is the constant 0x04; ignored.

    if (pkg < 0 || pkg >= _maxFragments) return null;

    final int slot = fid % _frameBuffers;
    if (_lastFid[slot] != fid) {
      _buf[slot] = List<Uint8List?>.filled(_maxFragments, null);
      _count[slot] = 0;
      _total[slot] = 0;
      _lastFid[slot] = fid;
    }

    final Uint8List? existing = _buf[slot][pkg];
    _buf[slot][pkg] = Uint8List.fromList(datagram.sublist(_headerLen));
    if (existing == null) {
      _count[slot] += 1; // a repeated fragment is not counted twice
    }

    if (eof == 1) {
      _total[slot] = pkg + 1;
    }

    if (_total[slot] > 0 && _count[slot] == _total[slot]) {
      return _join(slot);
    }
    return null;
  }

  Uint8List _join(int slot) {
    final int n = _total[slot];
    var len = 0;
    for (int i = 0; i < n; i++) {
      len += _buf[slot][i]!.length;
    }
    final Uint8List jpg = Uint8List(len);
    var off = 0;
    for (int i = 0; i < n; i++) {
      final Uint8List frag = _buf[slot][i]!;
      jpg.setRange(off, off + frag.length, frag);
      off += frag.length;
    }
    // Trim the camera footer (anything after the JPEG EOI marker).
    final int eoi = _lastIndexOfEoi(jpg);
    return eoi >= 0 ? Uint8List.sublistView(jpg, 0, eoi + 2) : jpg;
  }

  static int _lastIndexOfEoi(Uint8List bytes) {
    for (int i = bytes.length - 2; i >= 0; i--) {
      if (bytes[i] == jpegEoiHi && bytes[i + 1] == jpegEoiLo) return i;
    }
    return -1;
  }
}
