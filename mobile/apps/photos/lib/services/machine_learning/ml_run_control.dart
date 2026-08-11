enum MlStopReason { foregroundActive, backgroundDeadline, controller, manual }

class MlRunControl {
  final _stopListeners = <void Function(MlStopReason)>{};

  MlStopReason? _stopReason;

  bool get stopRequested => _stopReason != null;
  MlStopReason? get stopReason => _stopReason;

  void requestStop(MlStopReason reason) {
    if (_stopReason != null) return;
    _stopReason = reason;
    for (final listener in List.of(_stopListeners)) {
      listener(reason);
    }
  }

  void Function() addStopListener(void Function(MlStopReason) listener) {
    _stopListeners.add(listener);
    final reason = _stopReason;
    if (reason != null) {
      listener(reason);
    }
    return () => _stopListeners.remove(listener);
  }
}
