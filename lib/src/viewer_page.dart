import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:hnd_viewer/protocol.dart';
import 'package:hnd_viewer/recording.dart';
import 'package:hnd_viewer/src/sensor_chart.dart';

/// Live viewer: connects to the camera and shows the stream plus gyro roll.
class ViewerPage extends StatefulWidget {
  const ViewerPage({super.key});

  @override
  State<ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<ViewerPage> {
  CameraClient? _client;
  StreamSubscription<Uint8List>? _frameSub;
  StreamSubscription<GyroSample>? _gyroSub;

  Uint8List? _frame;
  final RollFilter _roll = RollFilter();
  final List<DateTime> _frameTimes = [];

  RecordingSession? _session;
  final Stopwatch _recordClock = Stopwatch();
  bool _recording = false;

  bool _connected = false;
  String _status = 'Disconnected';

  double _extraRotation = 180;
  bool _autoRotate = true;
  bool _mirror = false;
  bool _mirrorVertical = false;
  double _brightness = 100;
  double _smoothing = 85;
  double _fps = 0;

  bool _showSensorData = false;
  GyroSample? _lastGyro;

  /// Rolling buffer feeding the live strip chart (newest sample appended).
  static const int _sensorBufferMax = 300;
  final List<SensorPoint> _sensorBuffer = [];

  @override
  void dispose() {
    _disconnect();
    super.dispose();
  }

  Future<void> _connect() async {
    final client = CameraClient();
    _client = client;
    _frameSub = client.frames.listen(_onFrame);
    _gyroSub = client.gyro.listen(_onGyro);
    setState(() => _status = 'Connecting…');
    try {
      await client.start();
      if (!mounted) return;
      setState(() {
        _connected = true;
        _status = 'Streaming';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Connect failed: $e');
      await _teardown(client);
    }
  }

  void _onFrame(Uint8List bytes) {
    final now = DateTime.now();
    _frameTimes.add(now);
    _frameTimes
        .removeWhere((t) => now.difference(t) > const Duration(seconds: 5));
    // Record the raw JPEG bytes as-is; rotation/flip/brightness are view
    // transforms applied only when rendering.
    if (_recording) {
      _session?.addFrame(bytes, _recordClock.elapsed);
    }
    setState(() {
      _frame = bytes;
      _fps = _frameTimes.length / 5.0;
    });
  }

  void _onGyro(GyroSample s) {
    final double? rawRoll = rollFromAxes(s.x, s.y, s.z);
    _roll.update(rawRoll);
    _lastGyro = s;
    _sensorBuffer.add(SensorPoint(x: s.x, y: s.y, z: s.z, roll: rawRoll ?? 0));
    if (_sensorBuffer.length > _sensorBufferMax) {
      _sensorBuffer.removeRange(0, _sensorBuffer.length - _sensorBufferMax);
    }
    if (_recording) {
      _session?.addGyro(s, _recordClock.elapsed);
    }
    setState(() {});
  }

  Future<void> _disconnect() async {
    await _teardown(_client);
    _client = null;
    if (mounted) {
      setState(() {
        _connected = false;
        _frame = null;
        _status = 'Disconnected';
        _fps = 0;
      });
    }
  }

  Future<void> _teardown(CameraClient? client) async {
    if (client == null) return;
    await _frameSub?.cancel();
    await _gyroSub?.cancel();
    _frameSub = null;
    _gyroSub = null;
    await client.stop();
  }

  void _updateSmoothing(double v) {
    _smoothing = v;
    // Reference mapping: alpha = 1 - (smoothing/100) * 0.95.
    _roll.alpha = 1 - (v / 100) * 0.95;
  }

  Future<void> _saveSnapshot() async {
    final frame = _frame;
    if (frame == null) return;
    final String baseName = 'hnd_${DateTime.now().millisecondsSinceEpoch}';
    try {
      final String message;
      if (Platform.isAndroid || Platform.isIOS) {
        // Mobile: save to the system gallery via `gal`.
        await Gal.putImageBytes(frame, name: baseName);
        message = 'Snapshot saved to gallery';
      } else {
        // Desktop: write a plain file to ~/Downloads — no photo-library
        // permission prompt, and it can be run again freely.
        final Directory dir = await _downloadsDirectory();
        final File file =
            File('${dir.path}${Platform.pathSeparator}$baseName.jpg');
        await file.writeAsBytes(frame, flush: true);
        message = 'Snapshot saved: ${file.path}';
      }
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Snapshot failed: $e')));
      }
    }
  }

  /// The user's Downloads directory (created if missing), used for desktop
  /// snapshots. Falls back to the system temp dir if no home is set.
  Future<Directory> _downloadsDirectory() async {
    final String? home = Platform.isWindows
        ? Platform.environment['USERPROFILE']
        : Platform.environment['HOME'];
    final Directory dir = home == null
        ? Directory.systemTemp
        : Directory('$home${Platform.pathSeparator}Downloads');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> _toggleRecording() async {
    if (!_recording) {
      // Start a fresh session; frames arriving right after this are captured
      // with the stopwatch clock relative to the recording start.
      final session = RecordingSession();
      _recordClock..reset()..start();
      session.start(Duration.zero);
      setState(() {
        _session = session;
        _recording = true;
      });
      return;
    }

    // Stop: freeze the session, then encode the buffered frames to MP4.
    final session = _session;
    setState(() => _recording = false);
    _recordClock.stop();
    if (session == null) return;
    session.stop();
    final writer = FfmpegMp4Writer();
    try {
      await writer.start();
      for (final RecordedFrame f in session.frames) {
        await writer.writeFrame(f.jpeg, f.elapsed);
      }
      final String path = await writer.finish();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Recording saved: $path')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Recording failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          Expanded(child: _buildStage()),
          SizedBox(width: 300, child: _buildPanel()),
        ],
      ),
    );
  }

  Widget _buildStage() {
    // With auto-rotate off the stream keeps its manual (_extraRotation)
    // orientation and ignores the gyro roll entirely.
    final double roll =
        _autoRotate && _roll.valid ? (_roll.angle ?? 0) : 0;
    final double angleRad = (_extraRotation + roll) * math.pi / 180;
    final b = _brightness / 100;
    final brightness = <double>[
      b, 0, 0, 0, 0, //
      0, b, 0, 0, 0, //
      0, 0, b, 0, 0, //
      0, 0, 0, 1, 0,
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Only rotate/flip/brighten the actual video frame. The "No video"
        // placeholder must stay upright, so it is rendered outside the
        // Transform.rotate (the camera image is mounted 180° rotated, hence
        // the default _extraRotation).
        final Widget stage = _frame == null
            ? const Center(child: Text('No video — connect to the camera'))
            : LayoutBuilder(
                builder: (context, videoConstraints) {
                  final double size = math.min(
                      videoConstraints.maxWidth, videoConstraints.maxHeight);
                  return Center(
                    child: Transform.rotate(
                      angle: angleRad,
                      child: Transform.flip(
                        flipX: _mirror,
                        flipY: _mirrorVertical,
                        child: ColorFiltered(
                          colorFilter: ColorFilter.matrix(brightness),
                          child: SizedBox(
                            width: size,
                            height: size,
                            child: Image.memory(_frame!,
                                gaplessPlayback: true, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
        return Column(
          children: [
            // Video area on top; the square video is still sized by
            // min(width, height) of the space left above the sensor chart.
            Expanded(
              child: Container(
                color: const Color(0xFF05070A),
                alignment: Alignment.center,
                child: stage,
              ),
            ),
            if (_showSensorData)
              SizedBox(
                width: double.infinity,
                height: 120,
                child: SensorChart(points: _sensorBuffer),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPanel() {
    final roll = _roll.valid ? _roll.angle ?? 0 : 0;
    return Material(
      color: const Color(0xFF141A1E),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: ListView(
          children: [
          Text(
            'HND-NE3-D Ear Camera',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  _status,
                  style: TextStyle(
                    color: _connected ? Colors.lightGreen : Colors.blueGrey,
                    fontSize: 12,
                  ),
                ),
              ),
              FilledButton(
                onPressed: _connected ? _disconnect : _connect,
                child: _buttonLabel(_connected ? 'Disconnect' : 'Connect'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonal(
                  onPressed: _frame != null ? _saveSnapshot : null,
                  child: _buttonLabel('Snapshot'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: _frame != null ? _toggleRecording : null,
                  child: _buttonLabel(_recording ? 'Stop recording' : 'Record'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _slider('Extra rotation', _extraRotation, -180, 360, null, (v) {
            setState(() => _extraRotation = v);
          }, '${_extraRotation.round()}°'),
          _slider('Brightness', _brightness, 20, 300, null, (v) {
            setState(() => _brightness = v);
          }, '${_brightness.round()}%'),
          _slider('Smoothing', _smoothing, 0, 100, null, (v) {
            setState(() => _updateSmoothing(v));
          }, '${_smoothing.round()}%'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-rotate', style: TextStyle(fontSize: 13)),
            value: _autoRotate,
            onChanged: (v) => setState(() => _autoRotate = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Show sensor data', style: TextStyle(fontSize: 13)),
            value: _showSensorData,
            onChanged: (v) => setState(() => _showSensorData = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mirror horizontally', style: TextStyle(fontSize: 13)),
            value: _mirror,
            onChanged: (v) => setState(() => _mirror = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mirror vertically', style: TextStyle(fontSize: 13)),
            value: _mirrorVertical,
            onChanged: (v) => setState(() => _mirrorVertical = v),
          ),
          if (_showSensorData && _lastGyro != null) ...[
            const SizedBox(height: 8),
            _sensorReadout(_lastGyro!),
          ],
          const Divider(height: 24),
          Text(
            'roll: ${roll.toStringAsFixed(1)}° '
            '${_roll.valid ? '' : '(invalid)'}\n'
            'fps: ${_fps.toStringAsFixed(1)}',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Color(0xFF8FE3A5),
              height: 1.5,
            ),
          ),
          ],
        ),
      ),
    );
  }

  /// Monospace readout of the raw sensor sample (bytes 0..19 of the gyro
  /// datagram), laid out as fixed columns so the labels never shift as the
  /// values change. Lines: x, y, z, roll, mid, tail.
  Widget _sensorReadout(GyroSample gyro) {
    const TextStyle mono = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      color: Color(0xFF8FE3A5),
    );
    // Labels share one fixed column; numeric values share a right-aligned,
    // fixed-width column.
    const double labelWidth = 48;
    const double valueWidth = 72;

    final String mid = gyro.mid
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');

    Widget line(String labelText, Widget value) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          children: [
            SizedBox(
              width: labelWidth,
              child: Text(labelText, style: mono),
            ),
            value,
          ],
        ),
      );
    }

    // x/y/z raw int16 (6 chars covers -32768..32767) and the uint16 tail.
    Widget intValue(String text) {
      return SizedBox(
        width: valueWidth,
        child: Text(text, style: mono, textAlign: TextAlign.right),
      );
    }

    final double angle = _roll.angle ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line('x', intValue('${gyro.x}'.padLeft(6))),
        line('y', intValue('${gyro.y}'.padLeft(6))),
        line('z', intValue('${gyro.z}'.padLeft(6))),
        line(
          'roll',
          Row(
            children: [
              intValue(angle.toStringAsFixed(1).padLeft(6)),
              // Marker goes after the value so the label/value columns never
              // shift when validity toggles.
              Text(_roll.valid ? '°' : '° (invalid)', style: mono),
            ],
          ),
        ),
        // 12 unknown bytes as hex, right-aligned over the remaining width so
        // the (longer) value never pushes the label.
        line(
          'mid',
          Expanded(
            child: Text(mid, style: mono, textAlign: TextAlign.right),
          ),
        ),
        line('tail', intValue('${gyro.tail}'.padLeft(5))),
      ],
    );
  }

  /// One-line button label; never wraps.
  Widget _buttonLabel(String text) => Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      );

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    int? divisions,
    ValueChanged<double> onChanged,
    String display,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12)),
            Text(display, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
