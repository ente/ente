import 'dart:async';

import 'package:ente_contacts/contacts.dart' as contacts;
import 'package:locker/services/authenticated_session.dart';
import 'package:locker/services/configuration.dart';
import 'package:locker/services/contacts.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LockerContactsDisplayService {
  static final Logger _logger = Logger('LockerContactsDisplayService');
  static Future<void> _pendingOperation = Future.value();

  static Future<void> init({required SharedPreferences preferences}) async {
    contacts.ContactsDisplayService.instance.init(
      contactsServiceFactory: () => contacts.ContactsService(
        preferences: preferences,
        api: LockerContactsApi(authenticatedSession()),
      ),
    );
    scheduleEnsureReady();
  }

  static Future<void> ensureReady() async {
    final config = Configuration.instance;
    final userId = config.getUserID();
    if (userId == null || !config.hasConfiguredAccount()) {
      return;
    }
    authenticatedSession();
    await contacts.ContactsDisplayService.instance.ensureReady(
      baseUrl: config.getHttpEndpoint(),
      userId: userId,
    );
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
}
