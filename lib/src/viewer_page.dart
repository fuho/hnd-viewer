import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:hnd_viewer/protocol.dart';

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

  bool _connected = false;
  String _status = 'Disconnected';

  double _extraRotation = 180;
  bool _mirror = false;
  double _brightness = 100;
  double _smoothing = 85;
  double _fps = 0;

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
    setState(() {
      _frame = bytes;
      _fps = _frameTimes.length / 5.0;
    });
  }

  void _onGyro(GyroSample s) {
    _roll.update(rollFromAxes(s.x, s.y, s.z));
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
    final roll = _roll.valid ? (_roll.angle ?? 0) : 0;
    final angleRad = (_extraRotation + roll) * math.pi / 180;
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
        final Widget video = _frame == null
            ? const Center(child: Text('No video — connect to the camera'))
            : Image.memory(_frame!, gaplessPlayback: true, fit: BoxFit.cover);
        return Container(
          color: const Color(0xFF05070A),
          alignment: Alignment.center,
          child: Transform.rotate(
            angle: angleRad,
            child: Transform.flip(
              flipX: _mirror,
              child: ColorFiltered(
                colorFilter: ColorFilter.matrix(brightness),
                child: SizedBox(
                  width: size,
                  height: size,
                  child: video,
                ),
              ),
            ),
          ),
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
            title: const Text('Mirror horizontally', style: TextStyle(fontSize: 13)),
            value: _mirror,
            onChanged: (v) => setState(() => _mirror = v),
          ),
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
