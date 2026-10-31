import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ente_auth/events/codes_updated_event.dart';
import 'package:ente_auth/models/code.dart';
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
  final _logger = Logger('IOSAutoFillService');
  final bool _isIOS;
  late Future<List<Code>> Function() _readCodes;
  late String Function() _scope;
  late int Function() _timeOffset;
  SharedPreferences? _preferences;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Future<void> _queue = Future.value();
  int _revision = 0;
  bool isSupported = false;
  bool isEnabled = false;

  Future<void> init({
    required Future<List<Code>> Function() readCodes,
    required String Function() scope,
    required int Function() timeOffset,
  }) async {
    if (!_isIOS || _preferences != null) return;
    _readCodes = readCodes;
    _scope = scope;
    _timeOffset = timeOffset;
    try {
      isSupported = await channel.invokeMethod<bool>('isSupported') ?? false;
      if (!isSupported) return;
      _preferences = await SharedPreferences.getInstance();
      isEnabled = _preferences!.getBool(enabledKey) ?? false;
      WidgetsBinding.instance.addObserver(this);
      _subscriptions.add(
        Bus.instance.on<CodesUpdatedEvent>().listen(
          (_) => unawaited(refresh()),
        ),
      );
      _subscriptions.add(
        Bus.instance.on<SignedInEvent>().listen((_) => unawaited(refresh())),
      );
      if (isEnabled) {
        await refresh();
      } else {
        // Also removes shared Keychain material left behind by an uninstall.
        await channel.invokeMethod<void>('clear');
      }
    } catch (_) {
      _logger.warning('Could not initialize iOS AutoFill');
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

  Future<void> _publish(int revision) async {
    if (!isEnabled || revision != _revision) return;
    final scope = _scope();
    final codes = await _readCodes();
    // A pending read must never republish after disabling or logging out.
    if (!isEnabled || revision != _revision) return;
    if (scope != _scope()) {
      await channel.invokeMethod<void>('clear');
      return;
    }
    final entries = codes
        .where(
          (code) =>
              !code.hasError &&
              !code.isTrashed &&
              code.type == Type.totp &&
              code.issuer.toLowerCase() != 'steam' &&
              code.generatedID != null,
        )
        .map(
          (code) => {
            'id': '$scope:${code.generatedID}',
            'issuer': code.issuer,
            'account': code.account,
            'secret': code.secret,
            'algorithm': code.algorithm.name,
            'digits': code.digits,
            'period': code.period,
          },
        )
        .toList();
    await channel.invokeMethod<void>(
      'publish',
      jsonEncode({
        'version': 1,
        'timeOffsetMilliseconds': _timeOffset(),
        'entries': entries,
      }),
    );
  }

  Future<void> refresh() async {
    if (!isSupported || !isEnabled) return;
    final revision = _revision;
    try {
      await _serialize(() => _publish(revision));
    } catch (_) {
      if (revision != _revision) return;
      // Fail closed rather than retain deleted or outdated credentials.
      try {
        await disable();
      } catch (_) {
        _logger.warning('Could not clear iOS AutoFill data');
      }
      _logger.warning(
        'AutoFill disabled because its snapshot could not be updated',
      );
    }
  }

  Future<bool> enable() async {
    if (!isSupported) return false;
    final revision = ++_revision;
    final authenticated = await channel.invokeMethod<bool>('authenticate');
    if (authenticated != true || revision != _revision) return false;
    isEnabled = true;
    try {
      await _serialize(() => _publish(revision));
      if (!isEnabled || revision != _revision) return false;
      await _preferences!.setBool(enabledKey, true);
      notifyListeners();
      return true;
    } catch (_) {
      await disable();
      rethrow;
    }
  }

  Future<void> disable() async {
    if (!isSupported) return;
    isEnabled = false;
    ++_revision;
    notifyListeners();
    // Do not wait on a possibly slow vault read to revoke native access.
    // Method channel calls are ordered; the revision guard prevents later writes.
    await Future.wait<void>([
      channel.invokeMethod<void>('clear'),
      if (_preferences != null)
        _preferences!.setBool(enabledKey, false).then((_) {}),
    ]);
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
