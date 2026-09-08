import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:hnd_viewer/protocol.dart';
import 'package:hnd_viewer/recording.dart';

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
  double _brightness = 100;
  double _smoothing = 85;
  double _fps = 0;

  bool _showSensorData = false;
  GyroSample? _lastGyro;

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
    _roll.update(rollFromAxes(s.x, s.y, s.z));
    _lastGyro = s;
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
    final name = 'hnd_${DateTime.now().millisecondsSinceEpoch}';
    try {
      await Gal.putImageBytes(frame, name: name);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Snapshot saved: $name')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Snapshot failed: $e')));
      }
    }
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
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        // Only rotate/flip/brighten the actual video frame. The "No video"
        // placeholder must stay upright, so it is rendered outside the
        // Transform.rotate (the camera image is mounted 180° rotated, hence
        // the default _extraRotation).
        final Widget stage = _frame == null
            ? const Center(child: Text('No video — connect to the camera'))
            : Transform.rotate(
                angle: angleRad,
                child: Transform.flip(
                  flipX: _mirror,
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
              );
        return Container(
          color: const Color(0xFF05070A),
          alignment: Alignment.center,
          child: stage,
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
          const SizedBox(height: 4),
          Text(
            _status,
            style: TextStyle(
              color: _connected ? Colors.lightGreen : Colors.blueGrey,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _connected ? _disconnect : _connect,
                  child: Text(_connected ? 'Disconnect' : 'Connect'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: _frame != null ? _saveSnapshot : null,
                  child: const Text('Snapshot'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonal(
                  onPressed: _frame != null ? _toggleRecording : null,
                  child: Text(_recording ? 'Stop recording' : 'Record'),
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

  /// Plain monospace readout of the raw sensor sample (bytes 0..19 of the
  /// gyro datagram). Kept minimal: raw x/y/z, the 12 unknown bytes as hex, and
  /// the unknown uint16 tail.
  Widget _sensorReadout(GyroSample gyro) {
    final String mid = gyro.mid
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
    return Text(
      'x: ${gyro.x}  y: ${gyro.y}  z: ${gyro.z}\n'
      'mid: $mid\n'
      'tail: ${gyro.tail}',
      style: const TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
        color: Color(0xFF8FE3A5),
        height: 1.5,
      ),
    );
  }

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
