import 'dart:async';
import 'dart:io';

import 'package:ente_auth/events/codes_updated_event.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/models/watch_sync_payload.dart';
import 'package:ente_auth/services/preference_service.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/utils/totp_util.dart';
import 'package:ente_events/event_bus.dart';
import 'package:ente_logging/logging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Watch-to-phone copy request. The watch sends this map. Dart does not.
/// Keys are `action` and `id` only. The secret and the OTP stay out of it.
Map<String, String> watchCopyMessage({required String id}) {
  return {
    'action': 'copyCode',
    'id': id,
  };
}

/// Id from a `currentCode` call. Other keys, including a secret, are ignored.
String? watchCopyID(Object? arguments) {
  if (arguments is! Map) {
    return null;
  }
  final id = arguments['id'];
  if (id is! String || id.isEmpty) {
    return null;
  }
  return id;
}

/// Current code for [id], using [getOTP] so the phone clock and the user's
/// time offset match the clipboard. Returns null when the id is missing or
/// the account is not eligible for the watch. The secret is not part of the
/// result.
String? otpForWatchCopy({required String id, required List<Code> codes}) {
  final code = watchCopyChannelResult(id: id, codes: codes)?['code'];
  if (code is! String || code.isEmpty) {
    return null;
  }
  return code;
}

/// Channel result for a watch copy. `code` is the current OTP and `period`
/// is that token's step in seconds. The secret is not included. Only accounts
/// [isEligibleForWatchSync] would put on the watch are returned, so a guessed
/// id cannot mint an OTP for the rest of the vault. A missing or non-positive
/// period is reported as 30 so the phone can expire the pasteboard after one
/// default step.
Map<String, Object>? watchCopyChannelResult({
  required String id,
  required List<Code> codes,
}) {
  for (final code in codes) {
    if (!isEligibleForWatchSync(code)) {
      continue;
    }
    if (code.generatedID?.toString() != id) {
      continue;
    }
    final otp = getOTP(code);
    if (otp.isEmpty) {
      return null;
    }
    final period = code.period > 0 ? code.period : 30;
    return <String, Object>{
      'code': otp,
      'period': period,
    };
  }
  return null;
}

class WatchSyncService {
  WatchSyncService._privateConstructor();

  static final WatchSyncService instance =
      WatchSyncService._privateConstructor();

  static const _channel = MethodChannel('io.ente.auth/watch');
  static const _debounceDelay = Duration(milliseconds: 300);

  final _logger = Logger('WatchSyncService');

  /// Ids from the last payload `syncTokens` accepted. Memory only.
  final Set<String> _previousIds = {};

  StreamSubscription<CodesUpdatedEvent>? _subscription;
  Timer? _debounce;
  Future<void> _chain = Future<void>.value();
  bool _started = false;
  MethodChannel? _debugChannel;
  Future<List<Code>> Function()? _debugCodesLoader;
  CodeSortKey? _debugSortKey;

  /// Listens for code edits and pushes the eligible set to the watch.
  ///
  /// No-op off iOS. Schedules a push so a cold start sends the current vault.
  /// [CodesUpdatedEvent] is not fired on every load. Bursts share one push.
  /// Sort-key changes fire that same event from [PreferenceService.setCodeSortKey].
  void start() {
    if (kIsWeb || !Platform.isIOS) {
      return;
    }
    _begin();
  }

  /// Same listener as [start], without the iOS guard. Tests run off iOS.
  @visibleForTesting
  void debugStart() => _begin();

  void _begin() {
    if (_started) {
      return;
    }
    _started = true;
    _bindCopyHandler();
    _subscription ??= Bus.instance.on<CodesUpdatedEvent>().listen((_) {
      _scheduleSync();
    });
    _scheduleSync();
  }

  /// Test seam. Production [start] still no-ops off iOS and uses [CodeStore].
  @visibleForTesting
  void debugConfigure({
    required MethodChannel channel,
    required Future<List<Code>> Function() codesLoader,
    CodeSortKey sortKey = CodeSortKey.issuerName,
  }) {
    _debugChannel?.setMethodCallHandler(null);
    _debugChannel = channel;
    _debugCodesLoader = codesLoader;
    _debugSortKey = sortKey;
    if (_started) {
      _bindCopyHandler();
    }
  }

  @visibleForTesting
  void debugReset() {
    (_debugChannel ?? _channel).setMethodCallHandler(null);
    _subscription?.cancel();
    _subscription = null;
    _started = false;
    _debounce?.cancel();
    _debounce = null;
    _previousIds.clear();
    _chain = Future<void>.value();
    _debugChannel = null;
    _debugCodesLoader = null;
    _debugSortKey = null;
  }

  @visibleForTesting
  void debugScheduleSync() => _scheduleSync();

  @visibleForTesting
  Future<void> debugPushNow() {
    _chain = _chain.then((_) => _push());
    return _chain;
  }

  @visibleForTesting
  void debugBindCopyHandler() => _bindCopyHandler();

  @visibleForTesting
  Future<String?> debugCurrentCode(String id) async {
    final code = (await _currentCode(id))?['code'];
    if (code is! String || code.isEmpty) {
      return null;
    }
    return code;
  }

  void _bindCopyHandler() {
    (_debugChannel ?? _channel).setMethodCallHandler(_onWatchCall);
  }

  Future<Object?> _onWatchCall(MethodCall call) async {
    if (call.method != 'currentCode') {
      return null;
    }
    final id = watchCopyID(call.arguments);
    if (id == null) {
      return null;
    }
    try {
      return await _currentCode(id);
    } on Object {
      _logger.warning('Watch copy lookup failed');
      return null;
    }
  }

  Future<Map<String, Object>?> _currentCode(String id) async {
    final codes = _debugCodesLoader != null
        ? await _debugCodesLoader!()
        : await CodeStore.instance.getAllCodes();
    return watchCopyChannelResult(id: id, codes: codes);
  }

  void _scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDelay, () {
      _chain = _chain.then((_) => _push());
    });
  }

  Future<void> _push() async {
    try {
      final codes = _debugCodesLoader != null
          ? await _debugCodesLoader!()
          : await CodeStore.instance.getAllCodes();
      final payload = buildWatchPayload(
        codes,
        syncAll: watchSyncsAllAccounts,
        deletedIds: Set<String>.of(_previousIds),
        sortKey: _debugSortKey ?? PreferenceService.instance.codeSortKey(),
      );
      await (_debugChannel ?? _channel).invokeMethod<void>(
        'syncTokens',
        payload.toJson(),
      );
      _previousIds
        ..clear()
        ..addAll(payload.tokens.map((token) => token.id));
    } on MissingPluginException {
      _logger.warning('Watch sync channel is unavailable');
    } on PlatformException {
      _logger.warning('Watch sync failed');
    } on Object {
      _logger.warning('Watch sync failed');
    }
  }
}
