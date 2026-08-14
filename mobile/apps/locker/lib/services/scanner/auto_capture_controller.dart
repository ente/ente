import 'package:locker/services/scanner/scanner_models.dart';

enum AutoCaptureState { searching, arming, cooldown }

/// Time-based state machine for hands-free capture, fed once per analyzed
/// frame. A stabilizer-approved quad that keeps passing the gates for
/// [armHold] fires a capture, after which the frame must stay quad-free for
/// [clearHold] (with no capture processing pending) before re-arming, so a
/// document left in view is captured exactly once.
class AutoCaptureController {
  /// How long an eligible quad must be held before firing.
  static const armHold = Duration(milliseconds: 1200);

  /// Ineligible time tolerated while arming before progress resets.
  static const armGrace = Duration(milliseconds: 250);

  /// How long the frame must stay quad-free after a capture to re-arm.
  static const clearHold = Duration(milliseconds: 700);

  /// Cap on per-frame elapsed time, so stalls don't jump the timers.
  static const maxFrameGap = Duration(milliseconds: 200);

  /// Minimum quad area as a fraction of the mask area.
  static const minAreaFraction = 0.15;

  AutoCaptureState _state = AutoCaptureState.searching;
  double _progress = 0;
  Duration _graceElapsed = Duration.zero;
  Duration _clearElapsed = Duration.zero;
  DateTime? _lastFrameAt;

  AutoCaptureState get state => _state;

  /// Arming progress in [0, 1]; 0 outside [AutoCaptureState.arming].
  double get progress => _progress;

  /// Advances the machine with the stabilizer output for one frame. Returns
  /// true when the hold completed and a capture should fire now.
  bool onFrame(ScanQuad? stableQuad, {required bool captureBusy}) {
    final now = DateTime.now();
    final last = _lastFrameAt;
    _lastFrameAt = now;
    var dt = last == null ? Duration.zero : now.difference(last);
    if (dt.isNegative) dt = Duration.zero;
    if (dt > maxFrameGap) dt = maxFrameGap;

    final eligible =
        stableQuad != null && _areaFraction(stableQuad) >= minAreaFraction;

    switch (_state) {
      case AutoCaptureState.searching:
        if (eligible) {
          _state = AutoCaptureState.arming;
          _progress = 0;
          _graceElapsed = Duration.zero;
        }
        return false;
      case AutoCaptureState.arming:
        if (eligible) {
          _graceElapsed = Duration.zero;
          _progress += dt.inMicroseconds / armHold.inMicroseconds;
          if (_progress >= 1) {
            notifyCaptureStarted();
            return true;
          }
        } else {
          _graceElapsed += dt;
          if (_graceElapsed >= armGrace) {
            _state = AutoCaptureState.searching;
            _progress = 0;
          }
        }
        return false;
      case AutoCaptureState.cooldown:
        if (stableQuad != null || captureBusy) {
          _clearElapsed = Duration.zero;
        } else {
          _clearElapsed += dt;
          if (_clearElapsed >= clearHold) {
            _state = AutoCaptureState.searching;
          }
        }
        return false;
    }
  }

  /// Disarms until the document leaves the frame. Called for every capture,
  /// manual or automatic, so a document still in view is not re-captured.
  void notifyCaptureStarted() {
    _state = AutoCaptureState.cooldown;
    _progress = 0;
    _clearElapsed = Duration.zero;
  }

  void reset() {
    _state = AutoCaptureState.searching;
    _progress = 0;
    _graceElapsed = Duration.zero;
    _clearElapsed = Duration.zero;
    _lastFrameAt = null;
  }

  static double _areaFraction(ScanQuad quad) {
    var doubled = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = quad.corners[i];
      final b = quad.corners[(i + 1) % 4];
      doubled += a.dx * b.dy - b.dx * a.dy;
    }
    return doubled.abs() / 2 / (ScanQuad.maskSide * ScanQuad.maskSide);
  }
}
