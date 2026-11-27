import 'dart:async';
import 'dart:io';

import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/events/codes_updated_event.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/models/watch/snapshot.dart';
import 'package:ente_auth/models/watch/state.dart';
import 'package:ente_auth/services/preference_service.dart';
import 'package:ente_auth/services/watch/selection.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/utils/code_sort.dart';
import 'package:ente_events/event_bus.dart';
import 'package:ente_events/models/signed_out_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WatchService extends ChangeNotifier with WidgetsBindingObserver {
  WatchService._(this._preferences);

  static const _preferenceKey = 'watchSelection';
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

  static Future<void> onTagRenamed(String previousTag, String updatedTag) =>
      _instance?._reconcileTagChange(
        (tags) => tags.contains(previousTag)
            ? ({...tags}
                ..remove(previousTag)
                ..add(updatedTag))
            : null,
      ) ??
      Future.value();

  static Future<void> onTagDeleted(String tag) =>
      _instance?._reconcileTagChange(
        (tags) => tags.contains(tag) ? ({...tags}..remove(tag)) : null,
      ) ??
      Future.value();

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
  WatchSelection? _selection;
  bool _available = false;
  bool get isPlatformSupported => _available;
  bool _locked = true;
  bool _foreground = false;
  bool _pendingClear = false;
  int _generation = 0;
  Future<void> _tail = Future.value();
  Timer? _debounce;
  Completer<void>? _resumed;

  WatchSelection? get _currentSelection =>
      _selection?.scope == vaultScope() && _selection?.epoch == state.vaultEpoch
      ? _selection
      : null;

  WatchSharing? get sharing => _currentSelection?.watches[state.enrollmentID];

  static Set<String> get sharedTags =>
      _instance?._currentSelection?.watches.values
          .where((sharing) => sharing.mode == WatchSharingMode.tags)
          .expand((sharing) => sharing.tags)
          .toSet() ??
      const {};

  static bool tagRenameExpandsSharing(
    String previousTag,
    String updatedTag, {
    required bool destinationExists,
  }) =>
      _instance?._currentSelection?.watches.values.any(
        (sharing) =>
            sharing.mode == WatchSharingMode.tags &&
            ((!sharing.tags.contains(previousTag) &&
                    sharing.tags.contains(updatedTag)) ||
                (destinationExists &&
                    sharing.tags.contains(previousTag) &&
                    !sharing.tags.contains(updatedTag))),
      ) ??
      false;

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
        if (state.vaultEpoch != null) {
          await _save(
            WatchSelection(scope: vaultScope(), epoch: state.vaultEpoch!),
          );
        }
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
      final sharing = this.sharing;
      final codes = sharing == null
          ? <Code>[]
          : await CodeStore.instance.getAllCodes(requireCompleteRead: true);
      if (sharing != null) await _preferences.reload();
      if (!_current(generation, scope) ||
          state.enrollmentID != id ||
          state.vaultEpoch != epoch) {
        return;
      }
      var hideCodes = false;
      if (sharing != null) {
        sortAuthCodes(codes, PreferenceService.instance.codeSortKey());
        hideCodes = PreferenceService.instance.shouldHideCodes();
      }
      final snapshot = WatchSnapshot.fromCodes(
        sharing == null ? const [] : codes.where(sharing.includes),
        hideCodes: hideCodes,
      );
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

  Future<void> _save(WatchSelection selection) async {
    if (!await _preferences.setString(_preferenceKey, selection.encode())) {
      throw StateError('Could not save watch selection.');
    }
    _selection = selection;
    notifyListeners();
  }

  Future<void> _reconcile() async {
    await _preferences.reload();
    final scope = vaultScope();
    final stored = WatchSelection.decode(
      _preferences.getString(_preferenceKey),
    );
    if (stored == null || stored.scope != scope) {
      await _clear();
      await _save(WatchSelection(scope: scope, epoch: state.vaultEpoch!));
    } else if (stored.epoch != state.vaultEpoch) {
      await _save(WatchSelection(scope: scope, epoch: state.vaultEpoch!));
    } else {
      _selection = stored;
      notifyListeners();
    }
  }

  static Future<WatchState> _clearNative(SharedPreferences preferences) async {
    Object? preferenceError;
    try {
      if (!await preferences.remove(_preferenceKey)) {
        preferenceError = StateError('Could not clear watch selection.');
      }
    } on Object catch (error) {
      preferenceError = error;
    }
    final next = await _call('clear');
    if (preferenceError != null) throw preferenceError;
    return next;
  }

  Future<void> _clear() async {
    _selection = null;
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

  Future<void> share(WatchState target, String scope, WatchSharing sharing) =>
      _enqueue(() async {
        await _prepareChange(target, scope);
        final enrollmentID = state.phase == WatchPhase.approval
            ? state.requestID
            : state.enrollmentID;
        if (enrollmentID == null) {
          throw PlatformException(code: 'wrongEnrollment');
        }
        if (state.phase == WatchPhase.approval) {
          _accept(await _call('approve', {'enrollmentID': enrollmentID}));
        }
        if (scope != vaultScope() ||
            target.vaultEpoch != state.vaultEpoch ||
            !state.canPublish ||
            state.enrollmentID != enrollmentID) {
          throw PlatformException(code: 'wrongEnrollment');
        }
        if (_locked || !_foreground) {
          throw PlatformException(code: 'phoneLocked');
        }
        await _save(
          WatchSelection(
            scope: _selection!.scope,
            epoch: _selection!.epoch,
            watches: {..._selection!.watches, enrollmentID: sharing},
          ),
        );
        _schedule();
      });

  Future<void> disable(WatchState target, String scope) => _enqueue(() async {
    await _prepareChange(target, scope);
    _accept(await _call('disable', {'enrollmentID': target.enrollmentID}));
    await _save(
      WatchSelection(
        scope: _selection!.scope,
        epoch: _selection!.epoch,
        watches: {..._selection!.watches}..remove(target.enrollmentID),
      ),
    );
  });

  Future<void> _reconcileTagChange(
    Set<String>? Function(Set<String> tags) updateTags,
  ) => _enqueue(() async {
    await _preferences.reload();
    final scope = vaultScope();
    final stored = WatchSelection.decode(
      _preferences.getString(_preferenceKey),
    );
    final current = stored ?? _selection;
    if (current == null || current.scope != scope) return;
    if (state.vaultEpoch != null && current.epoch != state.vaultEpoch) return;
    var changed = false;
    final watches = <String, WatchSharing>{};
    current.watches.forEach((watch, sharing) {
      if (sharing.mode == WatchSharingMode.tags) {
        final nextTags = updateTags(sharing.tags);
        if (nextTags != null) {
          changed = true;
          watches[watch] = WatchSharing(
            mode: WatchSharingMode.tags,
            tags: nextTags,
          );
          return;
        }
      }
      watches[watch] = sharing;
    });
    if (!changed) return;
    await _save(
      WatchSelection(
        scope: current.scope,
        epoch: current.epoch,
        watches: watches,
      ),
    );
    _schedule();
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
