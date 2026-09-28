import 'dart:io';

import 'package:ente_account_deletion/account_deletion.dart';
import 'package:ente_configuration/base_configuration.dart';
import 'package:ente_lock_screen/lock_screen_host.dart';
import 'package:flutter/services.dart';
import 'package:locker/services/authenticated_session.dart';
import 'package:locker/services/collections/collections_service.dart';
import 'package:locker/services/favorites_service.dart';
import 'package:locker/services/files/offline/offline_file_storage.dart';
import 'package:logging/logging.dart';

class Configuration extends BaseConfiguration
    implements LockScreenHost, AccountDeletionHost {
  Configuration._privateConstructor();
  static final Configuration instance = Configuration._privateConstructor();

  final _logger = Logger('Configuration');
  // Survives page replacement and advances even when native cleanup fails.
  int _shareGeneration = 0;
  int get shareGeneration => _shareGeneration;

  @override
  EnteAppIdentity get appIdentity => const EnteAppIdentity(
    app: "locker",
    clientPackageName: "io.ente.locker",
    passkeyRedirectUrl: "entelocker://passkey",
    referralSourcePrefix: "locker",
  );

  @override
  List<String> get secureStorageKeys =>
      BaseConfiguration.accountSecureStorageKeys;

  @override
  Future<void> logout({bool autoLogout = false}) async {
    _shareGeneration++;
    if (Platform.isAndroid) {
      try {
        await const MethodChannel('io.ente.locker/shared_files')
            .invokeMethod<void>('clearPendingShares', _shareGeneration)
            .timeout(const Duration(seconds: 5));
      } catch (e, s) {
        _logger.warning('Failed to clear pending shares on logout', e, s);
      }
    }
    CollectionService.instance.clearCache();
    FavoritesService.instance.clearCache();
    await super.logout(autoLogout: autoLogout);
    clearAuthenticatedSession();
    try {
      await clearAllOfflineFileCopies();
    } catch (e, s) {
      _logger.warning('Failed to clear offline file copies on logout', e, s);
    }
  }
}
