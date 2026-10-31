import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:base32/base32.dart';
import 'package:ente_auth/events/codes_updated_event.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/utils/totp_util.dart';
import 'package:ente_events/event_bus.dart';
import 'package:ente_events/models/signed_in_event.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

class IOSAutoFillService extends ChangeNotifier with WidgetsBindingObserver {
  IOSAutoFillService._() : _isIOS = Platform.isIOS;

  @visibleForTesting
  IOSAutoFillService.forTesting() : _isIOS = true;

  static final instance = IOSAutoFillService._();
  static const channel = MethodChannel('io.ente.auth/autofill');
  static const enabledKey = 'ios_otp_autofill_enabled';
  static const cleanupPendingKey = 'ios_otp_autofill_cleanup_pending';
  final _logger = Logger('IOSAutoFillService');
  final bool _isIOS;
  late Future<List<Code>> Function() _readCodes;
  late String Function() _scope;
  late int Function() _timeOffset;
  SharedPreferences? _preferences;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Future<void> _queue = Future.value();
  int _revision = 0;
  int _dataRevision = 0;
  int _mutationsInFlight = 0;
  bool _cleanupPending = false;
  bool _initialized = false;
  bool _stateRestored = false;
  int _unavailableEntries = 0;
  bool isSupported = false;
  bool isEnabled = false;
  bool get hasPendingCleanup => _cleanupPending;
  int get unavailableEntries => _unavailableEntries;

  Future<void> init({
    required Future<List<Code>> Function() readCodes,
    required String Function() scope,
    required int Function() timeOffset,
  }) async {
    if (!_isIOS || _initialized) return;
    _initialized = true;
    _readCodes = readCodes;
    _scope = scope;
    _timeOffset = timeOffset;
    _preferences = await SharedPreferences.getInstance();
    _cleanupPending = _preferences!.getBool(cleanupPendingKey) ?? false;
    WidgetsBinding.instance.addObserver(this);
    _subscriptions.add(
      Bus.instance.on<CodesUpdatedEvent>().listen((_) => unawaited(refresh())),
    );
    _subscriptions.add(
      Bus.instance.on<SignedInEvent>().listen((_) => unawaited(refresh())),
    );
    try {
      isSupported = await channel.invokeMethod<bool>('isSupported') ?? false;
      isEnabled =
          isSupported &&
          !_cleanupPending &&
          (_preferences!.getBool(enabledKey) ?? false);
      _stateRestored = true;
      if (isEnabled) {
        await refresh();
      } else {
        // Also removes shared Keychain material left behind by an uninstall.
        await disable();
      }
    } catch (_) {
      _cleanupPending = true;
      _logger.warning('Could not initialize iOS AutoFill');
      try {
        await disable();
      } catch (_) {
        _logger.warning('iOS AutoFill cleanup is pending');
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.catchError((Object _) {});
    return result;
  }

  bool _isCurrent(int revision, int dataRevision) =>
      isEnabled &&
      revision == _revision &&
      dataRevision == _dataRevision &&
      _mutationsInFlight == 0;

  Future<void> _publish(
    int revision,
    int dataRevision,
    String generation,
  ) async {
    if (!_isCurrent(revision, dataRevision)) return;
    final scope = _scope();
    final codes = await _readCodes();
    // A pending read must never republish after disabling or logging out.
    if (!_isCurrent(revision, dataRevision)) return;
    if (scope != _scope()) {
      // Refresh invalidates immediately and queues a read for the new scope.
      // Do not await it from inside the publication queue itself.
      unawaited(refresh());
      return;
    }
    final entries = <Map<String, Object>>[];
    int unavailable = 0;
    for (final code in codes) {
      if (code.isTrashed) continue;
      if (code.hasError) {
        unavailable++;
        continue;
      }
      if (code.type != Type.totp ||
          code.issuer.toLowerCase() == 'steam' ||
          code.generatedID == null) {
        continue;
      }
      try {
        // Use exactly the main app's decoder, then canonicalize its bytes.
        // Legacy noncanonical pad bits must not disable an otherwise usable OTP.
        final secret = base32.decode(getSanitizedSecret(code.secret));
        if (secret.isEmpty ||
            code.digits < 1 ||
            code.digits > 10 ||
            code.period <= 0) {
          unavailable++;
          continue;
        }
        entries.add({
          'id': '$scope:${code.generatedID}',
          'issuer': code.issuer,
          'account': code.account,
          'secret': base32.encode(secret),
          'algorithm': code.algorithm.name,
          'digits': code.digits,
          'period': code.period,
        });
      } catch (_) {
        // Count invalid entries without logging their labels, secrets or errors.
        unavailable++;
      }
    }
    final nativeSkipped = await channel.invokeMethod<int>(
      'publish',
      jsonEncode({
        'version': 1,
        'generation': generation,
        'timeOffsetMilliseconds': _timeOffset(),
        'entries': entries,
      }),
    );
    if (_isCurrent(revision, dataRevision)) {
      _unavailableEntries = unavailable + (nativeSkipped ?? 0);
      notifyListeners();
    }
  }

  Future<void> refresh({bool rethrowOnFailure = false}) async {
    if (!isEnabled) {
      if (_cleanupPending) {
        try {
          await retryCleanup();
        } catch (_) {
          _logger.warning('iOS AutoFill cleanup is still pending');
        }
      }
      return;
    }
    if (!isSupported || _mutationsInFlight > 0) return;
    final revision = _revision;
    final dataRevision = ++_dataRevision;
    try {
      // Invalidate immediately, before waiting for older reads. The token also
      // fences publications already queued on the native side.
      final generation = await channel.invokeMethod<String>('invalidate');
      if (generation == null) throw StateError('Missing AutoFill generation');
      await _serialize(() => _publish(revision, dataRevision, generation));
    } catch (_) {
      if (!_isCurrent(revision, dataRevision)) return;
      // Fail closed rather than retain deleted or outdated credentials.
      try {
        await disable();
      } catch (_) {
        _logger.warning('Could not clear iOS AutoFill data');
      }
      _logger.warning(
        'AutoFill disabled because its snapshot could not be updated',
      );
      if (rethrowOnFailure) rethrow;
    }
  }

  Future<bool> enable() async {
    if (!isSupported) return false;
    if (_cleanupPending) await retryCleanup();
    final revision = ++_revision;
    final authenticated = await channel.invokeMethod<bool>('authenticate');
    if (authenticated != true || revision != _revision) return false;
    isEnabled = true;
    try {
      await refresh(rethrowOnFailure: true);
      if (!isEnabled || revision != _revision) return false;
      await _preferences!.setBool(enabledKey, true);
      notifyListeners();
      return true;
    } catch (_) {
      if (isEnabled) await disable();
      rethrow;
    }
  }

  Future<void> disable() async {
    if (!_isIOS) return;
    isEnabled = false;
    ++_revision;
    ++_dataRevision;
    _unavailableEntries = 0;
    _cleanupPending = true;
    notifyListeners();
    await retryCleanup();
  }

  Future<void> retryCleanup() async {
    if (!_isIOS || isEnabled) return;
    _cleanupPending = true;
    // Do not wait on a possibly slow vault read to revoke native access.
    // Native clear persists a tombstone before attempting key/file deletion.
    await Future.wait<void>([
      channel.invokeMethod<void>('clear'),
      (() async {
        _preferences ??= await SharedPreferences.getInstance();
        await _preferences!.setBool(enabledKey, false);
        await _preferences!.setBool(cleanupPendingKey, true);
      })(),
    ]);
    await _preferences!.setBool(cleanupPendingKey, false);
    _cleanupPending = false;
    notifyListeners();
  }

  // Called around database writes, not merely on a later UI event. Destructive
  // mutations are not acknowledged until the extension has been invalidated.
  Future<T> withInvalidatedSnapshot<T>(Future<T> Function() mutation) async {
    ++_mutationsInFlight;
    ++_dataRevision;
    try {
      // Startup sync can mutate the vault before init restores the opt-in.
      // Until then, assume a native snapshot from the previous run exists.
      if (_isIOS && (isEnabled || !_stateRestored)) {
        await channel.invokeMethod<String>('invalidate');
      } else if (_isIOS && _cleanupPending) {
        // Disabled UI state alone is not proof that old native data is gone.
        await retryCleanup();
      }
      return await mutation();
    } finally {
      --_mutationsInFlight;
      if (_mutationsInFlight == 0) unawaited(refresh());
    }
  }

  Future<void> openSettings() => channel.invokeMethod<void>('openSettings');

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}
