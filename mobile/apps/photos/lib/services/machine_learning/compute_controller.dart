import "dart:async";
import "dart:io";

import "package:ente_photos_platform/ente_photos_platform.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/compute_control_event.dart";
import "package:photos/events/device_health_changed_event.dart";
import "package:photos/main.dart";
import "package:photos/services/machine_learning/device_health_policy.dart";
import "package:photos/settings/local_settings.dart";

enum ComputeRunState { idle, runningML, generatingStream }

class ComputeController {
  final _logger = Logger("ComputeController");

  static const _healthRequestTimeout = Duration(seconds: 5);
  final kDefaultInteractionTimeout = Duration(seconds: Platform.isIOS ? 5 : 15);
  final LocalSettings _localSettings;
  final DeviceHealthSource _deviceHealthSource;
  final DeviceHealthPolicy _deviceHealthPolicy;
  // Process-lifetime subscription owned by this singleton.
  // ignore: cancel_subscriptions
  StreamSubscription<DeviceHealthSnapshot>? _deviceHealthSubscription;
  Timer? _deviceHealthRefreshTimer;
  int _deviceHealthGeneration = 0;

  bool _isDeviceHealthy = false;
  bool _isUserInteracting = true;
  bool _canRunCompute = false;
  bool _hasCompletedInitialHealthChecks = false;
  bool _temporaryInteractionOverride = false;
  bool _debugInteractionOverride = false;
  Future<void>? _initFuture;

  bool get interactionOverride =>
      _temporaryInteractionOverride || _debugInteractionOverride;

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

  ComputeController(
    this._localSettings, {
    DeviceHealthSource? deviceHealthSource,
    DeviceHealthPolicy deviceHealthPolicy = const DeviceHealthPolicy(),
  }) : _deviceHealthSource = deviceHealthSource ?? DeviceHealthClient.instance,
       _deviceHealthPolicy = deviceHealthPolicy {
    _logger.info('ComputeController constructor');
    unawaited(init());
    _logger.info('init done ');
  }

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

    _deviceHealthSubscription ??= _deviceHealthSource.updates.listen(
      _onDeviceHealthUpdate,
      onError: _onDeviceHealthError,
    );
    await _refreshDeviceHealth();
    _deviceHealthRefreshTimer ??= Timer.periodic(
      DeviceHealthPolicy.refreshInterval,
      (_) => unawaited(_refreshDeviceHealth()),
    );

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
        _waitingToRunML = false;
      }
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

  Future<void> _refreshDeviceHealth() async {
    final generation = _deviceHealthGeneration;
    try {
      final snapshot = await _deviceHealthSource.getSnapshot().timeout(
        _healthRequestTimeout,
      );
      if (generation == _deviceHealthGeneration) {
        _onDeviceHealthUpdate(snapshot);
      }
    } catch (error, stackTrace) {
      if (generation == _deviceHealthGeneration) {
        _onDeviceHealthError(error, stackTrace);
      }
    }
  }

  void _onDeviceHealthUpdate(DeviceHealthSnapshot snapshot) {
    _deviceHealthGeneration++;
    final evaluation = _deviceHealthPolicy.evaluate(
      snapshot,
      now: DateTime.now(),
    );
    if (!evaluation.isHealthy) {
      _logger.warning(
        'Device health is unacceptable: ${evaluation.issues.map((e) => e.name).join(', ')}',
      );
    }
    _setDeviceHealth(evaluation.isHealthy);
    _fireControlEvent();
  }

  void _onDeviceHealthError(Object error, [StackTrace? stackTrace]) {
    _deviceHealthGeneration++;
    _logger.warning('Failed to observe device health', error, stackTrace);
    _setDeviceHealth(false);
    _fireControlEvent();
  }
}
