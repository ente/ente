import 'dart:async';

import 'package:ente_contacts/contacts.dart' as contacts;
import 'package:locker/services/configuration.dart';
import 'package:locker/services/frb_contacts_rust_api.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LockerContactsDisplayService {
  static final Logger _logger = Logger('LockerContactsDisplayService');
  static PackageInfo? _packageInfo;
  static Future<void> _pendingOperation = Future.value();

  static Future<void> init({
    required SharedPreferences preferences,
    required PackageInfo packageInfo,
  }) async {
    contacts.ContactsDisplayService.instance.init(
      preferences: preferences,
      rustApi: const FrbContactsRustApi(),
    );
    _packageInfo = packageInfo;
    scheduleEnsureReady();
  }

  static Future<void> ensureReady() async {
    final session = buildSession();
    if (session == null) {
      return;
    }
    await contacts.ContactsDisplayService.instance.ensureReady(session);
  }

  static Future<void> resetLocalState() {
    return contacts.ContactsDisplayService.instance.resetLocalState();
  }

  static void scheduleEnsureReady() {
    unawaited(
      _enqueueOperation(() async {
        await _warmup();
      }),
    );
  }

  static void scheduleResetLocalState() {
    unawaited(
      _enqueueOperation(() async {
        await resetLocalState();
      }),
    );
  }

  static Future<void> _warmup() async {
    try {
      await ensureReady();
    } catch (error, stackTrace) {
      _logger.warning(
        'Failed to warm shared contacts display cache',
        error,
        stackTrace,
      );
    }
  }

  static Future<void> _enqueueOperation(Future<void> Function() operation) {
    final previous = _pendingOperation;
    late final Future<void> current;
    current = previous.catchError((_) {}).then((_) => operation());
    _pendingOperation = current.catchError((_) {});
    return current;
  }

  static contacts.ContactsSession? buildSession() {
    final packageInfo = _packageInfo;
    final token = Configuration.instance.getToken();
    final userId = Configuration.instance.getUserID();
    final accountKey = Configuration.instance.getKey();
    if (packageInfo == null ||
        token == null ||
        userId == null ||
        accountKey == null) {
      return null;
    }
    return contacts.ContactsSession(
      baseUrl: Configuration.instance.getHttpEndpoint(),
      authToken: token,
      userId: userId,
      accountKey: accountKey,
      clientPackage: packageInfo.packageName,
      clientVersion: packageInfo.version,
    );
  }
}
