import 'package:flutter/services.dart';

class ProcessLockState {
  const ProcessLockState({
    required this.origin,
    required this.operation,
    required this.heldFor,
  });

  factory ProcessLockState.fromMap(Map<dynamic, dynamic> map) {
    final origin = map['origin'];
    final operation = map['operation'];
    final heldForMillis = map['heldForMillis'];
    if (origin is! String || operation is! String || heldForMillis is! int) {
      throw const FormatException('Malformed process lock state');
    }
    return ProcessLockState(
      origin: origin,
      operation: operation,
      heldFor: Duration(milliseconds: heldForMillis),
    );
  }

  final String origin;
  final String operation;
  final Duration heldFor;

  @override
  String toString() =>
      'ProcessLockState(origin: $origin, operation: $operation, '
      'heldFor: ${heldFor.inMilliseconds}ms)';
}

class ProcessLockClient {
  ProcessLockClient({MethodChannel? methodChannel})
    : _methodChannel = methodChannel ?? const MethodChannel(_methodChannelName);

  static final instance = ProcessLockClient();
  static const _methodChannelName = 'io.ente.photos.platform/process_lock';

  final MethodChannel _methodChannel;

  Future<bool> tryAcquire({
    required String name,
    required String origin,
    required String operation,
  }) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'processLock.tryAcquire',
      {'name': name, 'origin': origin, 'operation': operation},
    );
    if (result == null) {
      throw const FormatException('processLock.tryAcquire returned no result');
    }
    return result;
  }

  Future<bool> release({required String name}) async {
    final result = await _methodChannel.invokeMethod<bool>(
      'processLock.release',
      {'name': name},
    );
    if (result == null) {
      throw const FormatException('processLock.release returned no result');
    }
    return result;
  }

  Future<ProcessLockState?> state({required String name}) async {
    final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
      'processLock.state',
      {'name': name},
    );
    if (result == null) return null;
    return ProcessLockState.fromMap(result);
  }
}
