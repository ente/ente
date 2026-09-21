import 'package:locker/services/scanner/scanner_models.dart';

enum AutoCaptureState { searching, arming, cooldown }

class AutoCaptureController {
  static const armHold = Duration(milliseconds: 700);

  static const armGrace = Duration(milliseconds: 250);

  static const clearHold = Duration(milliseconds: 700);

  static const minAreaFraction = 0.15;

  AutoCaptureState _state = AutoCaptureState.searching;
  double _progress = 0;
  Duration _armedElapsed = Duration.zero;
  Duration? _missingSince;
  Duration _missingGrace = armGrace;
  Duration? _clearSince;
  Duration? _lastFrameAt;

  AutoCaptureState get state => _state;

  double get progress => _progress;

  bool onFrame(
    ScanQuad? stableQuad, {
    required bool captureBusy,
    required Duration timestamp,
    bool resetProgress = false,
    bool? documentPresent,
  }) {
    final last = _lastFrameAt;
    if (timestamp.isNegative || (last != null && timestamp <= last)) {
      invalidateArming();
      return false;
    }
    _lastFrameAt = timestamp;
    final dt = last == null || resetProgress ? Duration.zero : timestamp - last;
    if (resetProgress) {
      invalidateArming();
      _clearSince = null;
    }

    final eligible =
        !captureBusy &&
        stableQuad != null &&
        stableQuad.area >= minAreaFraction;

    switch (_state) {
      case AutoCaptureState.searching:
        if (eligible) {
          _state = AutoCaptureState.arming;
          _progress = 0;
          _armedElapsed = Duration.zero;
          _missingSince = null;
        }
        return false;
      case AutoCaptureState.arming:
        if (eligible) {
          final missingSince = _missingSince;
          _missingSince = null;
          if (missingSince == null) {
            _armedElapsed += dt;
          } else if (timestamp - missingSince > _missingGrace) {
            _armedElapsed = Duration.zero;
          }
          _progress = _armedElapsed.inMicroseconds / armHold.inMicroseconds;
          if (_armedElapsed >= armHold) {
            notifyCaptureStarted();
            return true;
          }
        } else {
          if (_missingSince == null) {
            _missingSince = timestamp;
            _missingGrace = dt > armGrace ? dt + armGrace : armGrace;
            if (_missingGrace > armHold) _missingGrace = armHold;
          } else if (timestamp - _missingSince! >= _missingGrace) {
            invalidateArming();
          }
        }
        return false;
      case AutoCaptureState.cooldown:
        if ((documentPresent ?? stableQuad != null) || captureBusy) {
          _clearSince = null;
        } else {
          _clearSince ??= timestamp;
          if (timestamp - _clearSince! >= clearHold) {
            _state = AutoCaptureState.searching;
          }
        }
        return false;
    }
  }

  void notifyCaptureStarted() {
    _state = AutoCaptureState.cooldown;
    _progress = 0;
    _armedElapsed = Duration.zero;
    _missingSince = null;
    _clearSince = null;
  }

  void invalidateArming() {
    if (_state != AutoCaptureState.arming) return;
    _state = AutoCaptureState.searching;
    _progress = 0;
    _armedElapsed = Duration.zero;
    _missingSince = null;
    _missingGrace = armGrace;
  }

  void reset() {
    _state = AutoCaptureState.searching;
    _progress = 0;
    _armedElapsed = Duration.zero;
    _missingSince = null;
    _missingGrace = armGrace;
    _clearSince = null;
    _lastFrameAt = null;
  }
}
