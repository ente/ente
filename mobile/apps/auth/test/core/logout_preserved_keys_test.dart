import 'package:ente_auth/core/app_wide_preferences.dart';
import 'package:ente_auth/core/configuration.dart';
import 'package:ente_configuration/base_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('keysToClearOnLogout', () {
    test('clears everything when no prefixes are preserved', () {
      final keys = {"token", "email", "acct_1.token", "profilesV1"};

      expect(BaseConfiguration.keysToClearOnLogout(keys, const []), keys);
    });

    test('spares preserved prefixes and clears the rest', () {
      final keys = {
        "token",
        "email",
        "endpoint",
        "acct_1.token",
        "acct_1.email",
        "acct_2.has_opted_for_offline_mode",
        "profilesV1",
        "profilesActiveScope",
        "profilesNextId",
        "ls_is_app_lock_set",
        "should_show_lock_screen",
      };

      final cleared = BaseConfiguration.keysToClearOnLogout(
        keys,
        Configuration.instance.logoutPreservedKeyPrefixes,
      );

      expect(cleared, {"token", "email", "endpoint"});
    });
  });

  test('auth preserves other profiles, the registry and the app lock', () {
    expect(
      Configuration.instance.logoutPreservedKeyPrefixes,
      containsAll(["acct_", "profiles", "ls_", "should_show_lock_screen"]),
    );
  });

  group('app wide settings', () {
    // The legacy profile's keys carry no prefix, so its logout clears by
    // exclusion. Anything app wide left off the list is silently reset for
    // whichever profile survives the logout.
    test('every app wide key survives a legacy logout', () {
      final cleared = BaseConfiguration.keysToClearOnLogout(
        kAppWidePreferenceKeys.toSet(),
        Configuration.instance.logoutPreservedKeyPrefixes,
      );

      expect(cleared, isEmpty);
    });

    test('covers theme, language and local backup', () {
      // Spelled out so that renaming a constant without updating the list
      // fails here rather than in the field.
      expect(
        kAppWidePreferenceKeys,
        containsAll([
          'locale',
          'ente_auth_theme_mode',
          'adaptive_theme_preferences',
          'isAutoBackupEnabled',
          'autoBackupPath',
          'autoBackupTreeUri',
          'autoBackupIosBookmark',
          'lastBackupDay',
          'codeSortKey',
        ]),
      );
    });

    test('account owned keys are still cleared', () {
      // The mirror of the above: preserving one of these would leak the
      // previous account's state into the next session.
      final accountKeys = {
        BaseConfiguration.tokenKey,
        BaseConfiguration.encryptedTokenKey,
        BaseConfiguration.userIDKey,
        BaseConfiguration.emailKey,
        BaseConfiguration.keyAttributesKey,
        Configuration.hasOptedForOfflineModeKey,
        Configuration.autoBackupPasswordKey,
      };

      final cleared = BaseConfiguration.keysToClearOnLogout(
        accountKeys,
        Configuration.instance.logoutPreservedKeyPrefixes,
      );

      expect(cleared, accountKeys);
    });
  });
}
