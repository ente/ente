import "package:logging/logging.dart";

enum MlStopReason {
  foregroundActive,
  appPaused,
  backgroundDeadline,
  controller,
  logout,
  modeChanged,
  manual,
  corruptModel,
}

/// Durable per-run stop latch. Once stop is requested it holds for the rest
/// of that run — nothing resumes; work continues only when a new run starts.
class MlRunControl {
  final _logger = Logger("MlRunControl");
  bool _stopRequested = false;
  MlStopReason? _stopReason;
  void Function()? _onStop;

  bool get stopRequested => _stopRequested;
  MlStopReason? get stopReason => _stopReason;

  void requestStop(MlStopReason reason) {
    if (_stopRequested) return;
    _stopRequested = true;
    _stopReason = reason;
    _logger.info("ML run stop requested (${reason.name})");
    final onStop = _onStop;
    _onStop = null;
    onStop?.call();
  }

  /// One-shot notification for the active run. Fires immediately when stop
  /// was already requested.
  void attachOnStop(void Function() onStop) {
    if (_stopRequested) {
      onStop();
      return;
    }
    _onStop = onStop;
  }

  void detachOnStop() {
    _onStop = null;
  }
}
