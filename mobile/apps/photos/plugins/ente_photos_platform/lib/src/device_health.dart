import 'dart:async';

import 'package:flutter/services.dart';

enum DeviceHealthPlatform { android, ios }

enum DeviceSignalStatus { available, unsupported, unavailable }

enum DeviceBatteryHealth {
  good,
  cold,
  overheating,
  overVoltage,
  dead,
  failure,
  unknown,
}

enum DeviceThermalState {
  nominal,
  light,
  moderate,
  serious,
  critical,
  emergency,
  shutdown,
}

class DeviceBatterySnapshot {
  const DeviceBatterySnapshot({
    required this.status,
    this.levelPercent,
    this.temperatureCelsius,
    this.health,
    this.errorCode,
  });

  factory DeviceBatterySnapshot.fromMap(Map<dynamic, dynamic> map) {
    final status = _enumValue(
      DeviceSignalStatus.values,
      map['status'],
      'battery.status',
    );
    final level = _optionalInt(map['levelPercent'], 'battery.levelPercent');
    final temperature = _optionalDouble(
      map['temperatureCelsius'],
      'battery.temperatureCelsius',
    );
    final health = map['health'] == null
        ? null
        : _enumValue(
            DeviceBatteryHealth.values,
            map['health'],
            'battery.health',
          );
    final errorCode = _optionalString(map['errorCode'], 'battery.errorCode');
    _validateErrorCode(status, errorCode, 'battery');

    if (status == DeviceSignalStatus.available) {
      if (level == null || level < 0 || level > 100) {
        throw const FormatException(
          'Available battery signal requires a level from 0 to 100',
        );
      }
      if (temperature != null && !temperature.isFinite) {
        throw const FormatException('Battery temperature must be finite');
      }
    } else if (level != null || temperature != null || health != null) {
      throw const FormatException(
        'Unavailable battery signal contains observed values',
      );
    }

    return DeviceBatterySnapshot(
      status: status,
      levelPercent: level,
      temperatureCelsius: temperature,
      health: health,
      errorCode: errorCode,
    );
  }

  final DeviceSignalStatus status;
  final int? levelPercent;
  final double? temperatureCelsius;
  final DeviceBatteryHealth? health;
  final String? errorCode;
}

class DeviceThermalSnapshot {
  const DeviceThermalSnapshot({
    required this.status,
    this.state,
    this.errorCode,
  });

  factory DeviceThermalSnapshot.fromMap(Map<dynamic, dynamic> map) {
    final status = _enumValue(
      DeviceSignalStatus.values,
      map['status'],
      'thermal.status',
    );
    final state = map['state'] == null
        ? null
        : _enumValue(DeviceThermalState.values, map['state'], 'thermal.state');
    final errorCode = _optionalString(map['errorCode'], 'thermal.errorCode');
    _validateErrorCode(status, errorCode, 'thermal');
    if ((status == DeviceSignalStatus.available) != (state != null)) {
      throw const FormatException(
        'Thermal state must exist only when the signal is available',
      );
    }
    return DeviceThermalSnapshot(
      status: status,
      state: state,
      errorCode: errorCode,
    );
  }

  final DeviceSignalStatus status;
  final DeviceThermalState? state;
  final String? errorCode;
}

class DeviceMemorySnapshot {
  const DeviceMemorySnapshot({
    required this.status,
    this.totalBytes,
    this.errorCode,
  });

  factory DeviceMemorySnapshot.fromMap(Map<dynamic, dynamic> map) {
    final status = _enumValue(
      DeviceSignalStatus.values,
      map['status'],
      'memory.status',
    );
    final totalBytes = _optionalInt(map['totalBytes'], 'memory.totalBytes');
    final errorCode = _optionalString(map['errorCode'], 'memory.errorCode');
    _validateErrorCode(status, errorCode, 'memory');
    if (status == DeviceSignalStatus.available) {
      if (totalBytes == null || totalBytes <= 0) {
        throw const FormatException(
          'Available memory signal requires positive total bytes',
        );
      }
    } else if (totalBytes != null) {
      throw const FormatException(
        'Unavailable memory signal contains observed values',
      );
    }
    return DeviceMemorySnapshot(
      status: status,
      totalBytes: totalBytes,
      errorCode: errorCode,
    );
  }

  final DeviceSignalStatus status;
  final int? totalBytes;
  final String? errorCode;
}

class DeviceHealthSnapshot {
  const DeviceHealthSnapshot({
    required this.platform,
    required this.observedAt,
    required this.battery,
    required this.thermal,
  });

  factory DeviceHealthSnapshot.fromMap(Map<dynamic, dynamic> map) {
    final observedAtMs = _requiredInt(map['observedAtMs'], 'observedAtMs');
    if (observedAtMs <= 0) {
      throw const FormatException('Observation time must be positive');
    }
    return DeviceHealthSnapshot(
      platform: _enumValue(
        DeviceHealthPlatform.values,
        map['platform'],
        'platform',
      ),
      observedAt: DateTime.fromMillisecondsSinceEpoch(observedAtMs),
      battery: DeviceBatterySnapshot.fromMap(
        _requiredMap(map['battery'], 'battery'),
      ),
      thermal: DeviceThermalSnapshot.fromMap(
        _requiredMap(map['thermal'], 'thermal'),
      ),
    );
  }

  final DeviceHealthPlatform platform;
  final DateTime observedAt;
  final DeviceBatterySnapshot battery;
  final DeviceThermalSnapshot thermal;

  bool isFreshAt(DateTime now, Duration maximumAge) {
    if (maximumAge.isNegative) {
      throw ArgumentError.value(maximumAge, 'maximumAge', 'is negative');
    }
    final age = now.difference(observedAt);
    return !age.isNegative && age <= maximumAge;
  }
}

abstract interface class DeviceHealthSource {
  Future<DeviceHealthSnapshot> getSnapshot();

  Stream<DeviceHealthSnapshot> get updates;
}

class DeviceHealthClient implements DeviceHealthSource {
  DeviceHealthClient({MethodChannel? methodChannel, EventChannel? eventChannel})
    : _methodChannel = methodChannel ?? const MethodChannel(_methodChannelName),
      _eventChannel = eventChannel ?? const EventChannel(_eventChannelName);

  static final instance = DeviceHealthClient();
  static const _methodChannelName = 'io.ente.photos.platform/device_health';
  static const _eventChannelName =
      'io.ente.photos.platform/device_health_events';

  final MethodChannel _methodChannel;
  final EventChannel _eventChannel;
  Stream<DeviceHealthSnapshot>? _updates;

  @override
  Future<DeviceHealthSnapshot> getSnapshot() async {
    final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
      'deviceHealth.getSnapshot',
    );
    if (result == null) {
      throw const FormatException('Device health returned no snapshot');
    }
    return DeviceHealthSnapshot.fromMap(result);
  }

  Future<DeviceMemorySnapshot> getMemorySnapshot() async {
    final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
      'deviceHealth.getMemorySnapshot',
    );
    if (result == null) {
      throw const FormatException('Device memory returned no snapshot');
    }
    return DeviceMemorySnapshot.fromMap(result);
  }

  @override
  Stream<DeviceHealthSnapshot> get updates =>
      _updates ??= _eventChannel.receiveBroadcastStream().map((event) {
        if (event is! Map<dynamic, dynamic>) {
          throw const FormatException('Device health event is not a map');
        }
        return DeviceHealthSnapshot.fromMap(event);
      });
}

Map<dynamic, dynamic> _requiredMap(Object? value, String name) {
  if (value is! Map<dynamic, dynamic>) {
    throw FormatException('$name must be a map');
  }
  return value;
}

int _requiredInt(Object? value, String name) {
  if (value is! int) throw FormatException('$name must be an integer');
  return value;
}

int? _optionalInt(Object? value, String name) {
  if (value == null) return null;
  return _requiredInt(value, name);
}

double? _optionalDouble(Object? value, String name) {
  if (value == null) return null;
  if (value is! num) throw FormatException('$name must be numeric');
  return value.toDouble();
}

String? _optionalString(Object? value, String name) {
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw FormatException('$name must be a non-empty string');
  }
  return value;
}

void _validateErrorCode(
  DeviceSignalStatus status,
  String? errorCode,
  String signal,
) {
  if (status == DeviceSignalStatus.unavailable && errorCode == null) {
    throw FormatException('$signal unavailable without an error code');
  }
  if (status != DeviceSignalStatus.unavailable && errorCode != null) {
    throw FormatException('$signal error code without an unavailable status');
  }
}

T _enumValue<T extends Enum>(List<T> values, Object? value, String name) {
  if (value is! String) throw FormatException('$name must be a string');
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  throw FormatException('$name has unsupported value: $value');
}
