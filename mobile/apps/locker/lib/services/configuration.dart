import 'package:ente_account_deletion/account_deletion.dart';
import 'package:ente_configuration/base_configuration.dart';
import 'package:ente_lock_screen/lock_screen_host.dart';
import 'package:locker/services/collections/collections_service.dart';
import 'package:locker/services/favorites_service.dart';
import 'package:locker/services/files/offline/offline_file_storage.dart';
import 'package:logging/logging.dart';

class Configuration extends BaseConfiguration
    implements LockScreenHost, AccountDeletionHost {
  Configuration._privateConstructor();
  static final Configuration instance = Configuration._privateConstructor();

  final _logger = Logger('Configuration');

  @override
  EnteAppIdentity get appIdentity => const EnteAppIdentity(
    app: "locker",
    clientPackageName: "io.ente.locker",
    passkeyRedirectUrl: "entelocker://passkey",
    referralSourcePrefix: "locker",
  );

  @override
  // Provide all secure storage keys that should be wiped on logout.
  // Locker app uses the standard keys defined in BaseConfiguration.
  List<String> get secureStorageKeys =>
      BaseConfiguration.accountSecureStorageKeys;

  @override
  Future<void> logout({bool autoLogout = false}) async {
    CollectionService.instance.clearCache();
    FavoritesService.instance.clearCache();
    await super.logout(autoLogout: autoLogout);
    try {
      await clearAllOfflineFileCopies();
    } catch (e, s) {
      _logger.warning('Failed to clear offline file copies on logout', e, s);
    }
  }
}
