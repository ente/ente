import 'package:ente_auth/core/app_wide_preferences.dart';
import 'package:ente_auth/core/configuration.dart';
import 'package:ente_configuration/base_configuration.dart';
import 'package:ente_lock_screen/lock_screen_settings.dart';
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

  group('the app lock', () {
    // The lock guards the app, not any one vault, so a logout preserves its
    // keys while another profile is still signed in. This is the premise that
    // makes clearAppLockOnSignOut() necessary: nothing in the logout path will
    // ever remove these, so the final sign out has to do it explicitly.
    test('every app lock key survives a logout', () {
      final spared = BaseConfiguration.keysToClearOnLogout(
        LockScreenSettings.appLockStateKeys.toSet(),
        Configuration.instance.logoutPreservedKeyPrefixes,
      );

      expect(spared, isEmpty);
    });

    test('covers the keys that actually decide whether to lock', () {
      // Spelled out so that renaming a constant without updating the list
      // fails here rather than in the field. shouldShowLockScreen() consults
      // should_show_lock_screen, and the settings toggle reads
      // ls_is_app_lock_set; leaving either behind locks an app that has no
      // account left, or reports a lock with no credential behind it.
      expect(
        LockScreenSettings.appLockStateKeys,
        containsAll(['should_show_lock_screen', 'ls_is_app_lock_set']),
      );
    });
  });

  group('the local backup password', () {
    // It is deliberately absent from secureStorageKeys, so resetSecureStorage()
    // leaves it alone and LocalBackupService's SignedOutEvent listener is what
    // normally clears it. Removing an offline vault fires no such event, which
    // is why ProfileService.removeActive() has to clear it by hand.
    test('is not cleared by resetSecureStorage', () {
      expect(
        Configuration.instance.secureStorageKeys,
        isNot(contains(Configuration.autoBackupPasswordKey)),
      );
    });
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
        // Each vault backs up on its own schedule, so the marker is account
        // owned: a fresh account at this scope must not inherit it.
        kLastBackupDayKey,
      };

      final cleared = BaseConfiguration.keysToClearOnLogout(
        accountKeys,
        Configuration.instance.logoutPreservedKeyPrefixes,
      );

      expect(cleared, accountKeys);
    });
  });
}
