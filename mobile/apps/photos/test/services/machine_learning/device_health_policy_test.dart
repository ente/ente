import 'package:ente_photos_platform/ente_photos_platform.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photos/services/machine_learning/device_health_policy.dart';

void main() {
  const policy = DeviceHealthPolicy();
  final now = DateTime(2026, 8, 6, 12);
  Set<DeviceHealthIssue> issues(DeviceHealthSnapshot snapshot) =>
      policy.evaluate(snapshot, now: now).issues;

  test('fails closed without current required evidence', () {
    final unavailableBattery = _snapshot(
      now,
      battery: const DeviceBatterySnapshot(
        status: DeviceSignalStatus.unavailable,
        errorCode: 'battery_read_failed',
      ),
    );

    expect(issues(_snapshot(now.subtract(const Duration(minutes: 3)))), {
      DeviceHealthIssue.staleObservation,
    });
    expect(
      issues(unavailableBattery),
      contains(DeviceHealthIssue.batteryUnavailable),
    );
  });

  test('enforces the compute safety limits', () {
    expect(
      issues(_snapshot(now, battery: _androidBattery(level: 19))),
      contains(DeviceHealthIssue.lowBattery),
    );
    expect(
      issues(_snapshot(now, battery: _androidBattery(temperature: 42.1))),
      contains(DeviceHealthIssue.batteryTooHot),
    );
    expect(
      issues(
        _snapshot(
          now,
          thermal: const DeviceThermalSnapshot(
            status: DeviceSignalStatus.available,
            state: DeviceThermalState.serious,
          ),
        ),
      ),
      contains(DeviceHealthIssue.thermalTooHigh),
    );
  });

  test('uses battery evidence when Android thermal APIs are unsupported', () {
    const unsupportedThermal = DeviceThermalSnapshot(
      status: DeviceSignalStatus.unsupported,
    );

    expect(issues(_snapshot(now, thermal: unsupportedThermal)), isEmpty);
    expect(
      issues(
        _snapshot(
          now,
          battery: _androidBattery(health: DeviceBatteryHealth.unknown),
          thermal: unsupportedThermal,
        ),
      ),
      contains(DeviceHealthIssue.thermalUnavailable),
    );
  });

  test('requires only signals available on iOS devices', () {
    final unsupportedBattery = _snapshot(
      now,
      platform: DeviceHealthPlatform.ios,
      battery: const DeviceBatterySnapshot(
        status: DeviceSignalStatus.unsupported,
      ),
    );
    final unsupportedThermal = _snapshot(
      now,
      platform: DeviceHealthPlatform.ios,
      battery: const DeviceBatterySnapshot(
        status: DeviceSignalStatus.available,
        levelPercent: 80,
      ),
      thermal: const DeviceThermalSnapshot(
        status: DeviceSignalStatus.unsupported,
      ),
    );

    expect(issues(unsupportedBattery), isEmpty);
    expect(
      issues(unsupportedThermal),
      contains(DeviceHealthIssue.thermalUnavailable),
    );
  });
}

DeviceHealthSnapshot _snapshot(
  DateTime observedAt, {
  DeviceHealthPlatform platform = DeviceHealthPlatform.android,
  DeviceBatterySnapshot? battery,
  DeviceThermalSnapshot? thermal,
}) => DeviceHealthSnapshot(
  platform: platform,
  observedAt: observedAt,
  battery: battery ?? _androidBattery(),
  thermal:
      thermal ??
      const DeviceThermalSnapshot(
        status: DeviceSignalStatus.available,
        state: DeviceThermalState.nominal,
      ),
);

DeviceBatterySnapshot _androidBattery({
  int level = 80,
  double temperature = 30,
  DeviceBatteryHealth health = DeviceBatteryHealth.good,
}) => DeviceBatterySnapshot(
  status: DeviceSignalStatus.available,
  levelPercent: level,
  temperatureCelsius: temperature,
  health: health,
);
