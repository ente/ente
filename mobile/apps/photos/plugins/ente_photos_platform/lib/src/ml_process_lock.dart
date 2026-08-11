import 'package:flutter/services.dart';

enum MlProcessLockOrigin {
  foreground('fg'),
  background('bg');

  const MlProcessLockOrigin(this.channelValue);

  final String channelValue;
}

class MlProcessLockState {
  const MlProcessLockState({
    required this.origin,
    required this.operation,
    required this.heldDuration,
  });

  factory MlProcessLockState.fromMap(Map<dynamic, dynamic> map) {
    final origin = switch (map['origin']) {
      'fg' => MlProcessLockOrigin.foreground,
      'bg' => MlProcessLockOrigin.background,
      final value => throw FormatException(
        'ML process lock returned unsupported origin: $value',
      ),
    };
    final operation = map['operation'];
    final heldDurationMs = map['heldDurationMs'];
    if (operation is! String || operation.isEmpty) {
      throw const FormatException(
        'ML process lock operation must be a non-empty string',
      );
    }
    if (heldDurationMs is! int || heldDurationMs < 0) {
      throw const FormatException(
        'ML process lock held duration must be a non-negative integer',
      );
    }
    return MlProcessLockState(
      origin: origin,
      operation: operation,
      heldDuration: Duration(milliseconds: heldDurationMs),
    );
  }

  final MlProcessLockOrigin origin;
  final String operation;
  final Duration heldDuration;
}

class MlProcessLockAcquireResult {
  const MlProcessLockAcquireResult({
    required this.acquired,
    required this.holder,
  });

  final bool acquired;
  final MlProcessLockState holder;
}

class MlProcessLockClient {
  MlProcessLockClient({MethodChannel? methodChannel})
    : _methodChannel = methodChannel ?? const MethodChannel(_methodChannelName);

  static final instance = MlProcessLockClient();
  static const _methodChannelName = 'io.ente.photos.platform';

  final MethodChannel _methodChannel;
  Future<void>? _initialization;

  Future<MlProcessLockAcquireResult> tryAcquire({
    required String token,
    required MlProcessLockOrigin origin,
    required String operation,
  }) async {
    _validateNonEmpty(token, 'token');
    _validateNonEmpty(operation, 'operation');
    await _ensureInitialized();
    final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
      'mlLock.tryAcquire',
      {'token': token, 'origin': origin.channelValue, 'operation': operation},
    );
    if (result == null || result['acquired'] is! bool) {
      throw const FormatException(
        'ML process lock returned an invalid acquire result',
      );
    }
    final holder = result['holder'];
    if (holder is! Map<dynamic, dynamic>) {
      throw const FormatException(
        'ML process lock acquire result has no holder state',
      );
    }
    return MlProcessLockAcquireResult(
      acquired: result['acquired'] as bool,
      holder: MlProcessLockState.fromMap(holder),
    );
  }

  Future<bool> release(String token) async {
    _validateNonEmpty(token, 'token');
    await _ensureInitialized();
    final released = await _methodChannel.invokeMethod<bool>('mlLock.release', {
      'token': token,
    });
    if (released == null) {
      throw const FormatException(
        'ML process lock returned an invalid release result',
      );
    }
    return released;
  }

  Future<MlProcessLockState?> state() async {
    await _ensureInitialized();
    final state = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
      'mlLock.state',
    );
    return state == null ? null : MlProcessLockState.fromMap(state);
  }

  Future<void> _ensureInitialized() {
    return _initialization ??= _resetForCurrentDartSession();
  }

  Future<void> _resetForCurrentDartSession() async {
    final reset = await _methodChannel.invokeMethod<bool>(
      'mlLock.resetForInstance',
    );
    if (reset == null) {
      throw const FormatException(
        'ML process lock returned an invalid initialization result',
      );
    }
  }

  void _validateNonEmpty(String value, String name) {
    if (value.isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
  }
}
