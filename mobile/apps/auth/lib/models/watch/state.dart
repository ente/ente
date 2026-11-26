enum WatchPhase {
  unavailable,
  setup,
  approval,
  pending,
  synced,
  retiring,
  disabled,
  failed,
  replacement,
  ambiguous,
}

class WatchState {
  const WatchState({
    this.phase = WatchPhase.unavailable,
    this.enrollmentID,
    this.requestID,
    this.vaultEpoch,
  });

  factory WatchState.fromMap(Map<Object?, Object?> value) => WatchState(
    phase: WatchPhase.values.byName(value['phase']! as String),
    enrollmentID: value['enrollmentID'] as String?,
    requestID: value['requestID'] as String?,
    vaultEpoch: value['vaultEpoch'] as String?,
  );

  final WatchPhase phase;
  final String? enrollmentID;
  final String? requestID;
  final String? vaultEpoch;

  bool get canPublish =>
      enrollmentID != null &&
      enrollmentID == requestID &&
      (phase == WatchPhase.pending || phase == WatchPhase.synced);

  bool get canDisable =>
      enrollmentID != null &&
      phase != WatchPhase.retiring &&
      phase != WatchPhase.disabled;
}
