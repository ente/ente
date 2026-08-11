import "dart:async" show Zone, runZoned;

import "package:ente_photos_platform/ente_photos_platform.dart";
import "package:flutter/foundation.dart" show kDebugMode;
import "package:logging/logging.dart";
import "package:uuid/uuid.dart";

enum MlProcessOperation {
  fullRun,
  indexing,
  clustering,
  startupRemoteHydration,
  vectorMaintenance,
}

class MlPermitAttempt {
  const MlPermitAttempt._({this.permit, this.holder});

  factory MlPermitAttempt.acquired(MlProcessPermit permit) =>
      MlPermitAttempt._(permit: permit);

  factory MlPermitAttempt.denied(MlProcessLockState holder) =>
      MlPermitAttempt._(holder: holder);

  final MlProcessPermit? permit;
  final MlProcessLockState? holder;

  bool get acquired => permit != null;
}

class MlProcessPermit {
  MlProcessPermit._({
    required String token,
    required this.origin,
    required this.operation,
    required MlProcessLockClient client,
    required Logger logger,
    required void Function(String) onReleased,
  }) : _token = token,
       _client = client,
       _logger = logger,
       _onReleased = onReleased;

  final String _token;
  final MlProcessLockOrigin origin;
  final MlProcessOperation operation;
  final MlProcessLockClient _client;
  final Logger _logger;
  final void Function(String) _onReleased;
  bool _released = false;

  Future<T> run<T>(Future<T> Function() body) {
    if (_released) {
      throw StateError("Cannot run work with a released ML process permit");
    }
    return runZoned(
      body,
      zoneValues: {MlProcessLock._permitTokenZoneKey: _token},
    );
  }

  Future<void> release() async {
    if (_released) return;
    _released = true;
    try {
      final released = await _client.release(_token);
      if (!released) {
        _logger.warning(
          "ML process permit release was rejected for ${origin.name}/${operation.name}",
        );
        return;
      }
      _logger.info(
        "Released ML process permit for ${origin.name}/${operation.name}",
      );
    } finally {
      _onReleased(_token);
    }
  }
}

class MlProcessLock {
  MlProcessLock({MlProcessLockClient? client, Uuid? uuid})
    : _client = client ?? MlProcessLockClient.instance,
      _uuid = uuid ?? const Uuid();

  static final instance = MlProcessLock();

  final _logger = Logger("MlProcessLock");
  final MlProcessLockClient _client;
  final Uuid _uuid;
  final Set<String> _activeLocalTokens = {};
  static final _permitTokenZoneKey = Object();

  String newOperationToken() => _uuid.v4();

  Future<void> debugLogUnpermittedVectorMutation(String mutation) async {
    if (!kDebugMode) return;
    final zoneToken = Zone.current[_permitTokenZoneKey];
    if (zoneToken is String && _activeLocalTokens.contains(zoneToken)) return;
    try {
      final holder = await _client.state();
      if (holder != null) {
        _logger.warning(
          "Unpermitted vector mutation $mutation while "
          "${holder.origin.name}/${holder.operation} owns the ML permit",
        );
      }
    } catch (e, s) {
      _logger.warning("Failed to inspect ML permit for $mutation", e, s);
    }
  }

  Future<bool> runExclusive({
    required MlProcessLockOrigin origin,
    required MlProcessOperation operation,
    required Future<void> Function() body,
    Duration retryFor = Duration.zero,
    Duration retryInterval = const Duration(seconds: 5),
    bool Function()? shouldContinueWaiting,
  }) async {
    final token = newOperationToken();
    final deadline = DateTime.now().add(retryFor);
    while (true) {
      final attempt = await tryAcquire(
        origin: origin,
        operation: operation,
        token: token,
      );
      final permit = attempt.permit;
      if (permit != null) {
        try {
          await permit.run(body);
        } finally {
          await permit.release();
        }
        return true;
      }
      if (retryFor == Duration.zero ||
          DateTime.now().add(retryInterval).isAfter(deadline) ||
          shouldContinueWaiting?.call() == false) {
        if (retryFor != Duration.zero) {
          _logger.warning(
            "Timed out waiting for ${origin.name}/${operation.name} ML process permit",
          );
        }
        return false;
      }
      await Future<void>.delayed(retryInterval);
    }
  }

  Future<MlPermitAttempt> tryAcquire({
    required MlProcessLockOrigin origin,
    required MlProcessOperation operation,
    String? token,
  }) async {
    final operationToken = token ?? newOperationToken();
    try {
      final result = await _client.tryAcquire(
        token: operationToken,
        origin: origin,
        operation: operation.name,
      );
      if (!result.acquired) {
        _logger.info(
          "Denied ML process permit for ${origin.name}/${operation.name}; "
          "held by ${result.holder.origin.name}/${result.holder.operation} "
          "for ${result.holder.heldDuration.inMilliseconds}ms",
        );
        return MlPermitAttempt.denied(result.holder);
      }
      _logger.info(
        "Acquired ML process permit for ${origin.name}/${operation.name}",
      );
      _activeLocalTokens.add(operationToken);
      return MlPermitAttempt.acquired(
        MlProcessPermit._(
          token: operationToken,
          origin: origin,
          operation: operation,
          client: _client,
          logger: _logger,
          onReleased: _activeLocalTokens.remove,
        ),
      );
    } catch (e, s) {
      _logger.severe(
        "Failed to acquire ML process permit for ${origin.name}/${operation.name}; denying operation",
        e,
        s,
      );
      rethrow;
    }
  }
}
