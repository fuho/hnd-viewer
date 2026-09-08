/// Smooths roll with an exponential moving average plus a deadband.
///
/// Mirrors the reference implementation: the first valid sample snaps, a null
/// sample (near-vertical) holds the last good angle and clears [valid], and a
/// change below [deadband] is ignored to kill jitter.
class RollFilter {
  RollFilter({this.alpha = 0.15, this.deadband = 0.3});

  /// EMA factor applied when the change exceeds [deadband].
  ///
  /// Mutable so the UI can tune smoothing live.
  double alpha;

  /// Minimum change (degrees) before the smoothed value is updated.
  final double deadband;

  double? _smoothed;
  bool _valid = false;

  /// Whether the last update held a valid (non-vertical) angle.
  bool get valid => _valid;

  /// The current smoothed angle (degrees), or null before the first sample.
  double? get angle => _smoothed;

  /// Update with a new raw angle in degrees.
  ///
  /// A null [raw] marks the sample invalid (near-vertical) and holds the last
  /// good angle.
  void update(double? raw) {
    if (raw == null) {
      _valid = false;
      return;
    }
    if (!_valid) {
      _smoothed = raw;
      _valid = true;
      return;
    }
    double d = raw - _smoothed!;
    if (d > 180) {
      d -= 360;
    } else if (d < -180) {
      d += 360;
    }
    if (d.abs() >= deadband) {
      _smoothed = _smoothed! + alpha * d;
    }
  }
}
