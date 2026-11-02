import 'package:ente_account_deletion/account_deletion.dart';
import 'package:ente_base/models/database.dart';
import 'package:ente_configuration/base_configuration.dart';
import 'package:ente_lock_screen/lock_screen_host.dart';
import 'package:ente_lock_screen/lock_screen_settings.dart';
import 'package:locker/services/authenticated_session.dart';
import 'package:locker/services/collections/collections_service.dart';
import 'package:locker/services/favorites_service.dart';
import 'package:locker/services/files/offline/offline_file_storage.dart';
import 'package:locker/src/rust/third_party/ente_frb_lib/account_deletion.dart'
    as account_deletion;
import 'package:locker/src/rust/third_party/ente_frb_lib/recovery.dart'
    as recovery;
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Configuration extends BaseConfiguration
    implements LockScreenHost, AccountDeletionHost {
  Configuration._privateConstructor();

  static final Configuration instance = Configuration._privateConstructor();

  final _logger = Logger('Configuration');

  @override
  Future<void> init(List<EnteBaseDatabase> dbs) async {
    await super.init(dbs);
    if (!isLoggedIn()) {
      final preferences = await SharedPreferences.getInstance();
      await preferences.remove(LockScreenSettings.keyAppLockSet);
      await preferences.remove(LockScreenSettings.keyShouldShowLockScreen);
      await preferences.remove(LockScreenSettings.keyInvalidAttempts);
      await preferences.remove(LockScreenSettings.lastInvalidAttemptTime);
    }
  }

  @override
  EnteAppIdentity get appIdentity => const EnteAppIdentity(
    app: "locker",
    clientPackageName: "io.ente.locker",
    passkeyRedirectUrl: "entelocker://passkey",
    referralSourcePrefix: "locker",
  );

  @override
  List<String> get secureStorageKeys => [
    ...BaseConfiguration.accountSecureStorageKeys,
    LockScreenSettings.saltKey,
    LockScreenSettings.pin,
    LockScreenSettings.password,
  ];

  @override
  Future<AccountDeletionSummary?> getDeletionSummary() =>
      account_deletion.getDeletionSummary(session: authenticatedSession());

  @override
  Future<String> getDeleteChallenge() =>
      account_deletion.getDeleteChallenge(session: authenticatedSession());

  @override
  Future<void> deleteAccount({
    required String encryptedChallenge,
    required String reason,
    String? feedback,
  }) => account_deletion.deleteAccount(
    session: authenticatedSession(),
    encryptedChallenge: encryptedChallenge,
    reason: reason,
    feedback: feedback,
  );

  @override
  String recoveryKeyToMnemonic(String recoveryKeyHex) =>
      recovery.recoveryKeyToMnemonic(recoveryKeyHex: recoveryKeyHex);

  @override
  Future<void> logout({bool autoLogout = false}) async {
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
