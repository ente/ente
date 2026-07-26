import 'package:ente_auth/models/profile.dart';
import 'package:ente_auth/ui/settings_page.dart';
import 'package:flutter_test/flutter_test.dart';

// The settings header used to read straight from UserService's process wide
// email notifier, which showed the previous account's email after a switch.
void main() {
  const stale = "typed-but-never-signed-in@example.org";

  test('prefers the active profile over the notifier', () {
    final subtitle = settingsSubtitle(
      profile: const Profile(
        scope: "acct_1.",
        kind: ProfileKind.online,
        email: "active@example.org",
      ),
      email: stale,
      hasLoggedIn: true,
      offlineFallback: "Offline vault",
    );

    expect(subtitle, "active@example.org");
  });

  test('shows a named vault by its name', () {
    final subtitle = settingsSubtitle(
      profile: const Profile(
        scope: "acct_2.",
        kind: ProfileKind.offline,
        label: "Work laptop",
      ),
      email: stale,
      hasLoggedIn: false,
      offlineFallback: "Offline vault",
    );

    expect(subtitle, "Work laptop");
  });

  test('falls back to the generic name for an unnamed offline vault', () {
    final subtitle = settingsSubtitle(
      profile: const Profile(scope: "acct_3.", kind: ProfileKind.offline),
      email: stale,
      hasLoggedIn: false,
      offlineFallback: "Offline vault",
    );

    expect(subtitle, "Offline vault");
  });

  test('shows nothing when signed out with no profile', () {
    final subtitle = settingsSubtitle(
      profile: null,
      email: stale,
      hasLoggedIn: false,
      offlineFallback: "Offline vault",
    );

    expect(subtitle, isNull);
  });

  test('uses the notifier only when there is no profile yet', () {
    final subtitle = settingsSubtitle(
      profile: null,
      email: "someone@example.org",
      hasLoggedIn: true,
      offlineFallback: "Offline vault",
    );

    expect(subtitle, "someone@example.org");
  });

  group('showAccountSection', () {
    test('shown for a lone offline vault', () {
      // The switcher lives behind this row; without it an offline-only user
      // could never add or reach another account.
      expect(showAccountSection(hasLoggedIn: false, profileCount: 1), isTrue);
    });

    test('shown when signed in', () {
      expect(showAccountSection(hasLoggedIn: true, profileCount: 0), isTrue);
    });

    test('hidden when signed out with no profiles', () {
      expect(showAccountSection(hasLoggedIn: false, profileCount: 0), isFalse);
    });
  });
}
