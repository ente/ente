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
}
