import 'package:flutter/material.dart';

/// One gyro sample stored in the rolling buffer behind the strip chart.
class SensorPoint {
  const SensorPoint({
    required this.x,
    required this.y,
    required this.z,
    required this.roll,
  });

  /// Raw accelerometer X (int16).
  final int x;

  /// Raw accelerometer Y (int16).
  final int y;

  /// Raw accelerometer Z (int16).
  final int z;

  /// Roll in degrees (−180..180); 0 when the raw angle was invalid
  /// (near-vertical).
  final double roll;
}

const Color _xColor = Color(0xFFEF5350);
const Color _yColor = Color(0xFF42A5F5);
const Color _zColor = Color(0xFF66BB6A);
const Color _rollColor = Color(0xFFFFCA28);

/// Stage background the chart paints over.
const Color _chartBackground = Color(0xFF05070A);

/// Scrolling strip chart of the raw accelerometer axes (x/y/z, int16) plus
/// roll, drawn so the newest sample sits at the right edge.
///
/// x/y/z share a fixed y-range of −32768..32767 (raw int16); roll (°) is
/// normalized into the same range by [rollToInt16] so it overlays readably.
/// Wrap the widget in a `SizedBox(height: 120, ...)`; the painter fills its
/// canvas with the stage background colour. The widget repaints as samples
/// arrive because the caller rebuilds it (via `setState`) after each sample.
class SensorChart extends StatelessWidget {
  const SensorChart({super.key, required this.points});

  /// Rolling buffer of recent samples, oldest first. Mutated in place between
  /// frames by the owner, which triggers a rebuild + repaint.
  final List<SensorPoint> points;

  /// Multiplier mapping roll (°) onto the int16 plotting range, i.e.
  /// 32768/180 ≈ 182.
  static const double rollToInt16 = 32768.0 / 180.0;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SensorChartPainter(points),
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 8, top: 3),
          child: Wrap(
            spacing: 14,
            runSpacing: 2,
            children: const [
              _LegendEntry(color: _xColor, label: 'x'),
              _LegendEntry(color: _yColor, label: 'y'),
              _LegendEntry(color: _zColor, label: 'z'),
              _LegendEntry(color: _rollColor, label: 'roll (×182)'),
            ],
          ),
        ),
      ),
    );
  }
}

/// A colored monospace label naming one trace in the legend.
class _LegendEntry extends StatelessWidget {
  const _LegendEntry({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 11,
        color: color,
      ),
    );
  }
}

class _SensorChartPainter extends CustomPainter {
  _SensorChartPainter(this.points);

  final List<SensorPoint> points;

  /// Fixed plotting range covering the whole int16 span.
  static const double _minValue = -32768;
  static const double _maxValue = 32767;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect area = Offset.zero & size;
    canvas.drawRect(area, Paint()..color = _chartBackground);

    if (size.width <= 0 || size.height <= 0 || points.length < 2) return;

    // Keep the top edge clear for the legend widget drawn by the chart.
    final Rect plot = Rect.fromLTRB(0, 20, size.width, size.height - 6);
    if (plot.width <= 0 || plot.height <= 0) return;

    // Faint reference line at the mid-range (0) of the raw axes.
    final double midY = _yFor(0, plot.top, plot.bottom);
    canvas.drawLine(
      Offset(plot.left, midY),
      Offset(plot.right, midY),
      Paint()
        ..color = const Color(0x1AFFFFFF)
        ..strokeWidth = 1,
    );

    _drawTrace(canvas, plot, points, (p) => p.x.toDouble(), _xColor);
    _drawTrace(canvas, plot, points, (p) => p.y.toDouble(), _yColor);
    _drawTrace(canvas, plot, points, (p) => p.z.toDouble(), _zColor);
    _drawTrace(
      canvas,
      plot,
      points,
      (p) => p.roll * SensorChart.rollToInt16,
      _rollColor,
    );
  }

  /// Maps [value] (already on the int16 scale, clamped to −32768..32767) to a
  /// y pixel inside [top]..[bottom].
  double _yFor(double value, double top, double bottom) {
    final double clamped = value.clamp(_minValue, _maxValue).toDouble();
    return bottom -
        (clamped - _minValue) / (_maxValue - _minValue) * (bottom - top);
  }

  void _drawTrace(
    Canvas canvas,
    Rect plot,
    List<SensorPoint> pts,
    double Function(SensorPoint p) valueOf,
    Color color,
  ) {
    final int n = pts.length;
    if (n < 2) return;
    final double step = plot.width / (n - 1);
    final Path path = Path();
    for (int i = 0; i < n; i++) {
      final double dx = plot.left + i * step;
      final double dy = _yFor(valueOf(pts[i]), plot.top, plot.bottom);
      if (i == 0) {
        path.moveTo(dx, dy);
      } else {
        path.lineTo(dx, dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SensorChartPainter oldDelegate) {
    // The rolling list is mutated in place between frames: a repaint is
    // needed whenever a new sample became the last element (either appended,
    // or shifted in when the buffer is at its cap).
    if (!identical(points, oldDelegate.points)) return true;
    if (points.isEmpty || oldDelegate.points.isEmpty) {
      return points.isNotEmpty || oldDelegate.points.isNotEmpty;
    }
    return !identical(points.last, oldDelegate.points.last);
  }
}
