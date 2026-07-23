import "dart:async";
import "dart:io";

import "package:battery_info/battery_info_plugin.dart";
import "package:battery_info/model/android_battery_info.dart";
import "package:battery_info/model/iso_battery_info.dart";
import "package:flutter/foundation.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/compute_control_event.dart";
import "package:photos/events/device_health_changed_event.dart";
import "package:photos/main.dart";
import "package:photos/settings/local_settings.dart";
import "package:thermal/thermal.dart";

enum ComputeRunState { idle, runningML, generatingStream }

class ComputeController {
  final _logger = Logger("ComputeController");

  static const kMaximumTemperatureAndroid = 42; // 42 degree celsius
  static const kMinimumBatteryLevel = 20; // 20%
  final kDefaultInteractionTimeout = Duration(seconds: Platform.isIOS ? 5 : 15);
  static const kUnhealthyStates = ["over_heat", "over_voltage", "dead"];
  final LocalSettings _localSettings;

  static final _thermal = Thermal();
  IosBatteryInfo? _iosLastBatteryInfo;
  AndroidBatteryInfo? _androidLastBatteryInfo;
  ThermalStatus? _lastThermalStatus;

  bool _isDeviceHealthy = true;
  bool _isUserInteracting = true;
  bool _canRunCompute = false;
  bool _hasCompletedInitialHealthChecks = false;
  bool _temporaryInteractionOverride = false;
  bool _debugInteractionOverride = false;
  Future<void>? _initFuture;

  /// If true, user interaction is ignored and compute tasks can run regardless of user activity.
  bool get interactionOverride =>
      _temporaryInteractionOverride || _debugInteractionOverride;

  /// If true, compute tasks are paused regardless of device health or user activity.
  bool get computeBlocked => _computeBlocks.isNotEmpty;
  final Set<String> _computeBlocks = {};

  late Timer _userInteractionTimer;

  ComputeRunState _currentRunState = ComputeRunState.idle;
  bool _waitingToRunML = false;

  bool get isDeviceHealthy => _isDeviceHealthy;
  bool get shouldRunCompute =>
      _hasCompletedInitialHealthChecks &&
      _isDeviceHealthy &&
      _canRunMLGivenUserInteraction() &&
      !computeBlocked;

  void _setDeviceHealth(bool healthy) {
    if (_isDeviceHealthy == healthy) return;
    _isDeviceHealthy = healthy;
    _logger.info("Device health changed, healthy: $healthy");
    Bus.instance.fire(DeviceHealthChangedEvent(healthy));
  }

  ComputeController(this._localSettings) {
    _logger.info('ComputeController constructor');
    unawaited(init());
    _logger.info('init done ');
  }

  // Directly assign the values + Attach listener for compute controller
  Future<void> init() {
    return _initFuture ??= _initInternal();
  }

  Future<void> _initInternal() async {
    if (!isProcessBg) {
      // Initialize interaction tracking before any await to avoid first-tap races.
      _startInteractionTimer(kDefaultInteractionTimeout);

      await setMLInteractionOverride(
        turnOn: _localSettings.runMLDuringInteractionOverride,
        persist: false,
      );
    } else {
      // In background there is no user interaction signal, keep this false.
      _isUserInteracting = false;
    }

    // Thermal related
    _onThermalStateUpdate(await _thermal.thermalStatus);
    _thermal.onThermalStatusChanged.listen((ThermalStatus thermalState) {
      _onThermalStateUpdate(thermalState);
    });

    // Battery State
    if (Platform.isIOS) {
      if (kDebugMode) {
        _logger.fine(
          "iOS battery info stream is not available in simulator, disabling in debug mode",
        );
      } else {
        // Update Battery state for iOS
        _oniOSBatteryStateUpdate(await BatteryInfoPlugin().iosBatteryInfo);
        BatteryInfoPlugin().iosBatteryInfoStream.listen((
          IosBatteryInfo? batteryInfo,
        ) {
          _oniOSBatteryStateUpdate(batteryInfo);
        });
      }
    } else if (Platform.isAndroid) {
      // Update Battery state for Android
      _onAndroidBatteryStateUpdate(
        await BatteryInfoPlugin().androidBatteryInfo,
      );
      BatteryInfoPlugin().androidBatteryInfoStream.listen((
        AndroidBatteryInfo? batteryInfo,
      ) {
        _onAndroidBatteryStateUpdate(batteryInfo);
      });
    }

    _hasCompletedInitialHealthChecks = true;
    _fireControlEvent();
  }

  bool requestCompute({
    bool ml = false,
    bool stream = false,
    bool bypassInteractionCheck = false,
    bool bypassMLWaiting = false,
  }) {
    _logger.info(
      "Requesting compute: ml: $ml, stream: $stream, bypassInteraction: $bypassInteractionCheck, bypassMLWaiting: $bypassMLWaiting",
    );
    if (!_hasCompletedInitialHealthChecks) {
      _logger.info("Initial health checks are incomplete, denying request.");
      return false;
    }
    if (!_isDeviceHealthy) {
      _logger.info("Device not healthy, denying request.");
      return false;
    }
    if (!bypassInteractionCheck) {
      if (ml && !_canRunMLGivenUserInteraction()) {
        _logger.info("User interacting, denying ML request.");
        return false;
      }
      if (stream && !_canRunStreamGivenUserInteraction()) {
        _logger.info("User interacting, denying stream request.");
        return false;
      }
    }
    if (computeBlocked) {
      _logger.info("Compute is blocked by: $_computeBlocks, denying request.");
      return false;
    }
    bool result = false;
    if (ml) {
      result = _requestML();
    } else if (stream) {
      result = _requestStream(bypassMLWaiting);
    } else {
      _logger.severe("No compute request specified, denying request.");
    }
    return result;
  }

  ComputeRunState get computeState {
    return _currentRunState;
  }

  bool _requestML() {
    if (_currentRunState == ComputeRunState.idle) {
      _currentRunState = ComputeRunState.runningML;
      _waitingToRunML = false;
      _logger.info("ML request granted");
      return true;
    } else if (_currentRunState == ComputeRunState.runningML) {
      return true;
    }
    _logger.info(
      "ML request denied, current state: $_currentRunState, wants to run ML: $_waitingToRunML",
    );
    _waitingToRunML = true;
    return false;
  }

  bool _requestStream([bool bypassMLWaiting = false]) {
    if (_currentRunState == ComputeRunState.idle &&
        (bypassMLWaiting || !_waitingToRunML)) {
      _logger.info("Stream request granted");
      _currentRunState = ComputeRunState.generatingStream;
      return true;
    }
    _logger.info(
      "Stream request denied, current state: $_currentRunState, wants to run ML: $_waitingToRunML, bypassMLWaiting: $bypassMLWaiting",
    );
    return false;
  }

  void releaseCompute({bool ml = false, bool stream = false}) {
    _logger.info(
      "Releasing compute: ml: $ml, stream: $stream, current state: $_currentRunState",
    );

    if (ml) {
      if (_currentRunState == ComputeRunState.runningML) {
        _currentRunState = ComputeRunState.idle;
      }
      _waitingToRunML = false;
    } else if (stream) {
      if (_currentRunState == ComputeRunState.generatingStream) {
        _currentRunState = ComputeRunState.idle;
      }
    }
  }

  void onUserInteraction() {
    if (!_isUserInteracting) {
      _logger.info("User is interacting with the app");
      _isUserInteracting = true;
      _fireControlEvent();
    }
    _resetTimer();
  }

  bool _canRunMLGivenUserInteraction() {
    return !_isUserInteracting || interactionOverride;
  }

  bool _canRunStreamGivenUserInteraction() {
    return !_isUserInteracting;
  }

  void forceOverrideML({required bool turnOn}) {
    _logger.info("Forcing to turn on ML: $turnOn");
    _temporaryInteractionOverride = turnOn;
    _fireControlEvent();
  }

  Future<void> setMLInteractionOverride({
    required bool turnOn,
    bool persist = true,
  }) async {
    if (persist) {
      await _localSettings.setRunMLDuringInteractionOverride(turnOn);
    }
    _debugInteractionOverride = turnOn;
    _logger.info("ML debug interaction override set to: $turnOn");
    _fireControlEvent();
  }

  void blockCompute({required String blocker}) {
    _computeBlocks.add(blocker);
    _logger.info("Forcing to pauze compute due to: $blocker");
    _fireControlEvent();
  }

  void unblockCompute({required String blocker}) {
    _computeBlocks.remove(blocker);
    _logger.info("removed blocker: $blocker, now blocked: $computeBlocked");
    _fireControlEvent();
  }

  void _fireControlEvent() {
    if (!_hasCompletedInitialHealthChecks) {
      _logger.fine(
        "Skipping control event because initial health checks are incomplete",
      );
      return;
    }
    final shouldRunCompute = this.shouldRunCompute;
    if (shouldRunCompute != _canRunCompute) {
      _canRunCompute = shouldRunCompute;
      _logger.info(
        "Firing event: $shouldRunCompute      (device health: $_isDeviceHealthy, user interaction: $_isUserInteracting, mlInteractionOverride: $interactionOverride, blockers: $_computeBlocks)",
      );
      Bus.instance.fire(ComputeControlEvent(shouldRunCompute));
    }
  }

  void _startInteractionTimer(Duration timeout) {
    _userInteractionTimer = Timer(timeout, () {
      _isUserInteracting = false;
      _fireControlEvent();
    });
  }

  void _resetTimer() {
    _userInteractionTimer.cancel();
    _startInteractionTimer(kDefaultInteractionTimeout);
  }

  void _onAndroidBatteryStateUpdate(AndroidBatteryInfo? batteryInfo) {
    _androidLastBatteryInfo = batteryInfo;
    _setDeviceHealth(_computeIsAndroidDeviceHealthy());
    _fireControlEvent();
  }

  void _oniOSBatteryStateUpdate(IosBatteryInfo? batteryInfo) {
    _iosLastBatteryInfo = batteryInfo;
    _setDeviceHealth(_computeIsiOSDeviceHealthy());
    _fireControlEvent();
  }

  void _onThermalStateUpdate(ThermalStatus? thermalStatus) {
    final changed = _lastThermalStatus != thermalStatus;
    _lastThermalStatus = thermalStatus;
    if (changed) {
      _logger.info("Thermal status changed, status: $thermalStatus");
    }
    _setDeviceHealth(
      Platform.isAndroid
          ? _computeIsAndroidDeviceHealthy()
          : _computeIsiOSDeviceHealthy(),
    );
    _fireControlEvent();
  }

  bool _computeIsAndroidDeviceHealthy() {
    return _hasSufficientBattery(
          _androidLastBatteryInfo?.batteryLevel ?? kMinimumBatteryLevel,
        ) &&
        _isAcceptableTemperatureAndroid() &&
        _isBatteryHealthyAndroid() &&
        _isAcceptableThermalState();
  }

  bool _computeIsiOSDeviceHealthy() {
    return _hasSufficientBattery(
          _iosLastBatteryInfo?.batteryLevel ?? kMinimumBatteryLevel,
        ) &&
        _isAcceptableThermalState();
  }

  bool _isAcceptableThermalState() {
    switch (_lastThermalStatus) {
      case null:
        return true;
      case ThermalStatus.none:
      case ThermalStatus.light:
      case ThermalStatus.moderate:
        return true;
      case ThermalStatus.severe:
      case ThermalStatus.critical:
      case ThermalStatus.emergency:
      case ThermalStatus.shutdown:
        _logger.warning("Thermal status is unacceptable: $_lastThermalStatus");
        return false;
    }
  }

  bool _hasSufficientBattery(int batteryLevel) {
    return batteryLevel >= kMinimumBatteryLevel;
  }

  bool _isAcceptableTemperatureAndroid() {
    return (_androidLastBatteryInfo?.temperature ??
            kMaximumTemperatureAndroid) <=
        kMaximumTemperatureAndroid;
  }

  bool _isBatteryHealthyAndroid() {
    return !kUnhealthyStates.contains(_androidLastBatteryInfo?.health ?? "");
  }
}
