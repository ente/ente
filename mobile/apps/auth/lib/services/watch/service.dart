import 'dart:async';
import 'dart:io';

import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/events/codes_updated_event.dart';
import 'package:ente_auth/models/watch/snapshot.dart';
import 'package:ente_auth/models/watch/state.dart';
import 'package:ente_auth/services/preference_service.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/utils/code_sort.dart';
import 'package:ente_events/event_bus.dart';
import 'package:ente_events/models/signed_out_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WatchService extends ChangeNotifier with WidgetsBindingObserver {
  WatchService._(this._preferences);

  static const _preferenceKey = 'watchScope';
  static const _channel = MethodChannel('io.ente.auth/watch');
  static const _events = EventChannel('io.ente.auth/watch/state');
  static WatchService? _instance;
  static WatchService get instance => _instance!;
  static WatchService? get instanceOrNull => _instance;

  static Future<void> initialize() async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    final service = WatchService._(await SharedPreferences.getInstance());
    _instance = service;
    unawaited(service._start());
  }

  static void appLockChanged(bool locked) => _instance?._setLocked(locked);

  static void scheduleRefresh() => _instance?._schedule();

  static Future<void> clearBeforeLogout() async {
    if (_instance == null && !Platform.isIOS && !Platform.isAndroid) return;
    try {
      if (_instance case final service?) {
        await service._clearForLogout();
      } else {
        await _clearNative(await SharedPreferences.getInstance());
      }
    } on MissingPluginException {
      return;
    } on Object {
      _instance?._failed('watchUnavailable');
    }
  }

  final SharedPreferences _preferences;

  String vaultScope() {
    final config = Configuration.instance;
    if (config.hasConfiguredAccount()) return 'account:${config.getUserID()}';
    return config.hasOptedForOfflineMode() ? 'offline' : 'none';
  }

  WatchState state = const WatchState();
  String? errorCode;
  int omittedCount = 0;
  bool _available = false;
  bool get isPlatformSupported => _available;
  bool _locked = true;
  bool _foreground = false;
  bool _pendingClear = false;
  int _generation = 0;
  Future<void> _tail = Future.value();
  Timer? _debounce;
  Completer<void>? _resumed;

  Future<void> _start() async {
    _foreground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    Bus.instance.on<SignedOutEvent>().listen((_) {
      if (_pendingClear) _schedule();
    });
    try {
      final initialState = await _call('state');
      _available = true;
      _accept(initialState);
      _events.receiveBroadcastStream().listen((dynamic value) {
        final next = WatchState.fromMap(value as Map<Object?, Object?>);
        final changed =
            next.enrollmentID != state.enrollmentID ||
            next.requestID != state.requestID ||
            next.vaultEpoch != state.vaultEpoch;
        _accept(next);
        if (changed) _schedule();
      }, onError: (Object _) => _failed('watchUnavailable'));
      Bus.instance.on<CodesUpdatedEvent>().listen((_) => _schedule());
      await refresh();
    } on MissingPluginException {
      _available = false;
      notifyListeners();
    } on Object {
      _failed('watchUnavailable');
    }
  }

  static Future<WatchState> _call(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    final value = await _channel.invokeMapMethod<Object?, Object?>(
      method,
      arguments,
    );
    return WatchState.fromMap(value!);
  }

  void _accept(WatchState next) {
    state = next;
    notifyListeners();
  }

  void _failed(String code) {
    errorCode = code;
    notifyListeners();
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _schedule() {
    _generation++;
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 150),
      () => unawaited(refresh()),
    );
  }

  void _setLocked(bool locked) {
    _locked = locked;
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    _foreground = lifecycle == AppLifecycleState.resumed;
    if (_foreground) {
      _resumed?.complete();
      _resumed = null;
    }
    _schedule();
  }

  Future<void> refresh() => _enqueue(() async {
    if (!_available && !_pendingClear) return;
    try {
      errorCode = null;
      if (_pendingClear) {
        await _clear();
        _pendingClear = false;
        _available = true;
        await _saveScope(vaultScope());
        return;
      }
      _accept(await _call('state'));
      if (_locked || !_foreground || state.vaultEpoch == null) return;
      await _reconcile();
      final generation = _generation;
      final scope = vaultScope();
      if (scope == 'none' ||
          !_current(generation, scope) ||
          !state.canPublish) {
        return;
      }
      final id = state.enrollmentID!;
      final epoch = state.vaultEpoch!;
      final codes = await CodeStore.instance.getAllCodes(
        requireCompleteRead: true,
      );
      await _preferences.reload();
      if (!_current(generation, scope) ||
          state.enrollmentID != id ||
          state.vaultEpoch != epoch) {
        return;
      }
      sortAuthCodes(codes, PreferenceService.instance.codeSortKey());
      final snapshot = WatchSnapshot.fromCodes(codes);
      _accept(
        await _call('publish', {
          'enrollmentID': id,
          'vaultEpoch': epoch,
          'snapshot': snapshot.data,
        }),
      );
      omittedCount = snapshot.omittedCount;
      errorCode = null;
      notifyListeners();
    } on PlatformException catch (error) {
      _failed(error.code);
    } on Object {
      _failed('watchUnavailable');
    }
  });

  bool _current(int generation, String scope) =>
      !_locked &&
      _foreground &&
      generation == _generation &&
      scope == vaultScope();

  Future<void> _saveScope(String scope) async {
    if (!await _preferences.setString(_preferenceKey, scope)) {
      throw StateError('Could not save watch scope.');
    }
  }

  Future<void> _reconcile() async {
    await _preferences.reload();
    final scope = vaultScope();
    if (_preferences.getString(_preferenceKey) == scope) return;
    await _clear();
    await _saveScope(scope);
  }

  static Future<WatchState> _clearNative(SharedPreferences preferences) async {
    Object? preferenceError;
    try {
      if (!await preferences.remove(_preferenceKey)) {
        preferenceError = StateError('Could not clear watch scope.');
      }
    } on Object catch (error) {
      preferenceError = error;
    }
    final next = await _call('clear');
    if (preferenceError != null) throw preferenceError;
    return next;
  }

  Future<void> _clear() async {
    omittedCount = 0;
    _accept(await _clearNative(_preferences));
  }

  Future<void> _clearForLogout() {
    _generation++;
    return _enqueue(() async {
      _pendingClear = true;
      try {
        await _clear();
        _pendingClear = false;
      } on MissingPluginException {
        _pendingClear = false;
        rethrow;
      }
    });
  }

  Future<void> approve(WatchState target, String scope) => _enqueue(() async {
    await _prepareChange(target, scope);
    if (state.phase != WatchPhase.approval) {
      throw PlatformException(code: 'wrongEnrollment');
    }
    _accept(await _call('approve', {'enrollmentID': state.requestID}));
    _schedule();
  });

  Future<void> disable(WatchState target, String scope) => _enqueue(() async {
    await _prepareChange(target, scope);
    _accept(await _call('disable', {'enrollmentID': target.enrollmentID}));
  });

  Future<void> _prepareChange(WatchState target, String scope) async {
    if (!_foreground && !_locked) {
      _resumed ??= Completer<void>();
      await _resumed!.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw PlatformException(code: 'phoneLocked'),
      );
    }
    if (_locked || !_foreground) throw PlatformException(code: 'phoneLocked');
    _accept(await _call('state'));
    if (state.vaultEpoch == null) {
      throw PlatformException(code: 'watchUnavailable');
    }
    await _reconcile();
    if (_locked || !_foreground) {
      throw PlatformException(code: 'phoneLocked');
    }
    if (scope != vaultScope() ||
        target.vaultEpoch != state.vaultEpoch ||
        target.enrollmentID != state.enrollmentID ||
        target.requestID != state.requestID) {
      throw PlatformException(code: 'wrongEnrollment');
    }
  }
}
