import 'package:ente_photos_platform/ente_photos_platform.dart';

enum DeviceHealthIssue {
  staleObservation,
  batteryUnavailable,
  lowBattery,
  batteryTemperatureUnavailable,
  batteryTooHot,
  batteryHealthUnavailable,
  batteryUnhealthy,
  thermalUnavailable,
  thermalTooHigh,
}

class DeviceHealthEvaluation {
  const DeviceHealthEvaluation(this.issues);

  final Set<DeviceHealthIssue> issues;

  bool get isHealthy => issues.isEmpty;
}

class DeviceHealthPolicy {
  const DeviceHealthPolicy({
    this.minimumBatteryLevel = 20,
    this.maximumAndroidBatteryTemperature = 42,
    this.maximumObservationAge = const Duration(minutes: 2),
  });

  static const refreshInterval = Duration(minutes: 1);

  final int minimumBatteryLevel;
  final double maximumAndroidBatteryTemperature;
  final Duration maximumObservationAge;

  DeviceHealthEvaluation evaluate(
    DeviceHealthSnapshot snapshot, {
    required DateTime now,
  }) {
    if (!snapshot.isFreshAt(now, maximumObservationAge)) {
      return const DeviceHealthEvaluation({DeviceHealthIssue.staleObservation});
    }

    final issues = <DeviceHealthIssue>{};
    final battery = snapshot.battery;
    final batteryUnsupportedOnIOS =
        snapshot.platform == DeviceHealthPlatform.ios &&
        battery.status == DeviceSignalStatus.unsupported;
    if (!batteryUnsupportedOnIOS) {
      if (battery.status != DeviceSignalStatus.available) {
        issues.add(DeviceHealthIssue.batteryUnavailable);
      } else if (battery.levelPercent! < minimumBatteryLevel) {
        issues.add(DeviceHealthIssue.lowBattery);
      }
    }

    if (snapshot.platform == DeviceHealthPlatform.android &&
        battery.status == DeviceSignalStatus.available) {
      final temperature = battery.temperatureCelsius;
      if (temperature == null) {
        issues.add(DeviceHealthIssue.batteryTemperatureUnavailable);
      } else if (temperature > maximumAndroidBatteryTemperature) {
        issues.add(DeviceHealthIssue.batteryTooHot);
      }

      final health = battery.health;
      if (health == null || health == DeviceBatteryHealth.unknown) {
        issues.add(DeviceHealthIssue.batteryHealthUnavailable);
      } else if (health != DeviceBatteryHealth.good) {
        issues.add(DeviceHealthIssue.batteryUnhealthy);
      }
    }

    final thermal = snapshot.thermal;
    if (thermal.status == DeviceSignalStatus.available) {
      if (!_isAcceptableThermalState(thermal.state!)) {
        issues.add(DeviceHealthIssue.thermalTooHigh);
      }
    } else if (!(snapshot.platform == DeviceHealthPlatform.android &&
        thermal.status == DeviceSignalStatus.unsupported &&
        battery.temperatureCelsius != null &&
        battery.health != null &&
        battery.health != DeviceBatteryHealth.unknown)) {
      issues.add(DeviceHealthIssue.thermalUnavailable);
    }

    return DeviceHealthEvaluation(Set.unmodifiable(issues));
  }

  bool _isAcceptableThermalState(DeviceThermalState state) => switch (state) {
    DeviceThermalState.nominal ||
    DeviceThermalState.light ||
    DeviceThermalState.moderate => true,
    DeviceThermalState.serious ||
    DeviceThermalState.critical ||
    DeviceThermalState.emergency ||
    DeviceThermalState.shutdown => false,
  };
}
