import "dart:async";

import "package:ente_photos_platform/ente_photos_platform.dart";
import "package:logging/logging.dart";
import "package:synchronized/synchronized.dart";

enum MlOperation {
  fullRun,
  indexing,
  clustering,
  startupRemoteHydration,
  clipVectorMigration,
  clusterCentroidVectorMigration,
  clearData,
}

enum MlLockAttempt {
  ran,
  deniedFunnelBusy,
  deniedByOtherEngine,
  deniedChannelError,
  deniedTimeout,
}

enum MlRunDisposition { completed, denied, stopped, failed }

// All top-level ML work must enter through tryRunExclusive. The Dart funnel
// serializes this engine; the native lock excludes the other Flutter engine.
class MlProcessLock {
  MlProcessLock._();
  static final instance = MlProcessLock._();

  static const _lockName = "ml";
  static const _availabilityPollInterval = Duration(milliseconds: 500);
  final _logger = Logger("MlProcessLock");
  final Lock _funnel = Lock();
  MlOperation? _activeOperation;

  // Diagnostic only; do not use this to skip tryRunExclusive.
  bool get isBusy => _funnel.locked;

  MlOperation? get activeOperation => _activeOperation;

  // The callback must finish all protected work before returning.
  Future<MlLockAttempt> tryRunExclusive(
    MlOperation operation,
    Future<void> Function() body, {
    required bool background,
    bool waitForAvailability = false,
    Duration? waitDeadline,
  }) async {
    if (!waitForAvailability && _funnel.locked) {
      _logger.info(
        "Funnel busy with ${_activeOperation?.name}, denying ${operation.name}",
      );
      return MlLockAttempt.deniedFunnelBusy;
    }
    final nativeDeadline = waitDeadline == null
        ? null
        : DateTime.now().add(waitDeadline);
    try {
      return await _runSynchronized(
        operation,
        body,
        background: background,
        waitForAvailability: waitForAvailability,
        nativeDeadline: nativeDeadline,
        funnelTimeout: waitForAvailability ? waitDeadline : null,
      );
    } on TimeoutException {
      _logger.warning("Timed out waiting for the funnel (${operation.name})");
      return MlLockAttempt.deniedTimeout;
    }
  }

  Future<MlLockAttempt> _runSynchronized(
    MlOperation operation,
    Future<void> Function() body, {
    required bool background,
    required bool waitForAvailability,
    required DateTime? nativeDeadline,
    required Duration? funnelTimeout,
  }) {
    return _funnel.synchronized(timeout: funnelTimeout, () async {
      _activeOperation = operation;
      try {
        final origin = background ? "bg" : "fg";
        while (true) {
          final bool acquired;
          try {
            acquired = await ProcessLockClient.instance.tryAcquire(
              name: _lockName,
              origin: origin,
              operation: operation.name,
            );
          } catch (e, s) {
            // Fail closed: no protected ML without the lock.
            _logger.severe(
              "Process lock channel failure for ${operation.name}",
              e,
              s,
            );
            return MlLockAttempt.deniedChannelError;
          }
          if (acquired) break;
          if (!waitForAvailability) {
            unawaited(_logOwner(operation));
            return MlLockAttempt.deniedByOtherEngine;
          }
          if (nativeDeadline != null &&
              DateTime.now().isAfter(nativeDeadline)) {
            _logger.warning(
              "Timed out waiting for the ml lock (${operation.name})",
            );
            unawaited(_logOwner(operation));
            return MlLockAttempt.deniedTimeout;
          }
          await Future<void>.delayed(_availabilityPollInterval);
        }
        _logger.info("Acquired ml lock ($origin/${operation.name})");
        final heldSince = DateTime.now();
        try {
          await body();
          return MlLockAttempt.ran;
        } finally {
          try {
            await ProcessLockClient.instance.release(name: _lockName);
            final heldFor = DateTime.now().difference(heldSince);
            _logger.info(
              "Released ml lock ($origin/${operation.name}) after "
              "${heldFor.inSeconds}s",
            );
          } catch (e, s) {
            _logger.severe(
              "Failed to release ml lock after ${operation.name}",
              e,
              s,
            );
          }
        }
      } finally {
        _activeOperation = null;
      }
    });
  }

  Future<String> describeState() async {
    String native;
    try {
      final owner = await ProcessLockClient.instance.state(name: _lockName);
      native = owner == null
          ? "free"
          : "held by ${owner.origin}/${owner.operation} "
                "for ${owner.heldFor.inSeconds}s";
    } catch (e) {
      native = "unavailable ($e)";
    }
    return "Lock: $native · funnel: ${_activeOperation?.name ?? 'idle'}";
  }

  Future<void> _logOwner(MlOperation denied) async {
    try {
      final owner = await ProcessLockClient.instance.state(name: _lockName);
      _logger.info("ml lock denied for ${denied.name}, current owner: $owner");
    } catch (e) {
      _logger.warning("Could not fetch ml lock state after denial: $e");
    }
  }
}
