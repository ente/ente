import 'dart:convert';

import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/models/profile.dart';
import 'package:ente_auth/services/profile_service.dart';
import 'package:ente_auth/store/authenticator_db.dart';
import 'package:ente_auth/store/offline_authenticator_db.dart';
import 'package:ente_configuration/base_configuration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('key scoping', () {
    test('the legacy scope leaves keys untouched', () {
      final config = Configuration.instance;

      expect(config.scope, isEmpty);
      expect(config.scopedKey(BaseConfiguration.tokenKey), "token");
      expect(
        config.scopedKey(Configuration.authSecretKeyKey),
        "auth_secret_key",
      );
    });
  });

  group('database naming', () {
    test('the legacy scope keeps the original filenames', () {
      expect(AuthenticatorDB.databaseNameForScope(""), "ente.authenticator.db");
      expect(
        OfflineAuthenticatorDB.databaseNameForScope(""),
        "ente.offline_authenticator.db",
      );
    });

    test('each profile gets its own database files', () {
      expect(
        AuthenticatorDB.databaseNameForScope("acct_1."),
        "ente.acct_1.authenticator.db",
      );
      expect(
        OfflineAuthenticatorDB.databaseNameForScope("acct_1."),
        "ente.acct_1.offline_authenticator.db",
      );
      expect(
        AuthenticatorDB.databaseNameForScope("acct_1."),
        isNot(AuthenticatorDB.databaseNameForScope("acct_2.")),
      );
    });
  });

  group('seeding the profile list', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    test('a fresh install starts with no profiles', () async {
      SharedPreferences.setMockInitialValues({});

      await ProfileService.instance.init();

      expect(ProfileService.instance.profiles, isEmpty);
      expect(ProfileService.instance.activeScope, isEmpty);
      expect(ProfileService.instance.hasMultipleProfiles, isFalse);
    });

    test('an existing account becomes the legacy profile', () async {
      SharedPreferences.setMockInitialValues({
        BaseConfiguration.tokenKey: "a-token",
        BaseConfiguration.userIDKey: 7,
        BaseConfiguration.emailKey: "someone@example.org",
      });

      await ProfileService.instance.init();

      final profiles = ProfileService.instance.profiles;
      expect(profiles, hasLength(1));
      expect(profiles.single.scope, isEmpty);
      expect(profiles.single.kind, ProfileKind.online);
      expect(profiles.single.userID, 7);
      expect(profiles.single.email, "someone@example.org");
      expect(ProfileService.instance.activeScope, isEmpty);
    });

    test('an existing offline vault becomes the legacy profile', () async {
      SharedPreferences.setMockInitialValues({
        Configuration.hasOptedForOfflineModeKey: true,
      });

      await ProfileService.instance.init();

      final profiles = ProfileService.instance.profiles;
      expect(profiles, hasLength(1));
      expect(profiles.single.scope, isEmpty);
      expect(profiles.single.kind, ProfileKind.offline);
    });

    test('an empty list with an unregistered account is healed', () async {
      // A sign in that predates profile registration (or a registry lost to
      // an older bug) must resurface as a profile — otherwise the account
      // becomes unreachable the moment another one is added.
      SharedPreferences.setMockInitialValues({
        "profilesV1": <String>[],
        "profilesActiveScope": "",
        BaseConfiguration.tokenKey: "a-token",
        BaseConfiguration.userIDKey: 7,
        BaseConfiguration.emailKey: "someone@example.org",
      });
      await ProfileService.instance.init();

      final profiles = ProfileService.instance.profiles;
      expect(profiles, hasLength(1));
      expect(profiles.single.scope, isEmpty);
      expect(profiles.single.kind, ProfileKind.online);
      expect(profiles.single.userID, 7);
    });

    test('an empty list with an unregistered offline vault is healed', () async {
      SharedPreferences.setMockInitialValues({
        "profilesV1": <String>[],
        "profilesActiveScope": "",
        Configuration.hasOptedForOfflineModeKey: true,
      });
      await ProfileService.instance.init();

      final profiles = ProfileService.instance.profiles;
      expect(profiles, hasLength(1));
      expect(profiles.single.kind, ProfileKind.offline);
    });

    test('an empty list with no account data stays empty', () async {
      SharedPreferences.setMockInitialValues({
        "profilesV1": <String>[],
        "profilesActiveScope": "",
      });
      await ProfileService.instance.init();

      expect(ProfileService.instance.profiles, isEmpty);
    });

    test('an unknown active scope falls back to the first profile', () async {
      SharedPreferences.setMockInitialValues({
        "profilesV1": [
          json.encode(
            const Profile(scope: "acct_1.", kind: ProfileKind.online).toMap(),
          ),
        ],
        "profilesActiveScope": "acct_9.",
        "acct_1.token": "a-token",
      });

      await ProfileService.instance.init();

      expect(ProfileService.instance.activeScope, "acct_1.");
      expect(ProfileService.instance.activeProfile, isNotNull);
    });
  });

  group('reconciliation', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    test('drops profiles whose account data is gone', () async {
      // Logouts that live in shared packages (revoked session, too many
      // unlock attempts) clear the account's data without knowing about
      // profiles; the leftover record would be a vault that can never open.
      SharedPreferences.setMockInitialValues({
        "profilesV1": [
          json.encode(
            const Profile(
              scope: "acct_1.",
              kind: ProfileKind.online,
              userID: 1,
            ).toMap(),
          ),
          json.encode(
            const Profile(
              scope: "acct_2.",
              kind: ProfileKind.online,
              userID: 2,
            ).toMap(),
          ),
        ],
        "profilesActiveScope": "acct_1.",
        "acct_2.token": "a-token",
      });

      await ProfileService.instance.init();

      final profiles = ProfileService.instance.profiles;
      expect(profiles, hasLength(1));
      expect(profiles.single.scope, "acct_2.");
      expect(ProfileService.instance.activeScope, "acct_2.");
    });

    test('keeps offline vaults and encrypted-token accounts', () async {
      SharedPreferences.setMockInitialValues({
        "profilesV1": [
          json.encode(
            const Profile(scope: "acct_1.", kind: ProfileKind.offline).toMap(),
          ),
          json.encode(
            const Profile(scope: "acct_2.", kind: ProfileKind.online).toMap(),
          ),
        ],
        "profilesActiveScope": "acct_1.",
        "acct_1.${Configuration.hasOptedForOfflineModeKey}": true,
        "acct_2.${BaseConfiguration.encryptedTokenKey}": "encrypted",
      });

      await ProfileService.instance.init();

      expect(ProfileService.instance.profiles, hasLength(2));
      expect(ProfileService.instance.activeScope, "acct_1.");
    });
  });

  group('registering the active profile', () {
    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({
        "profilesV1": <String>[],
        "profilesActiveScope": "",
      });
      await ProfileService.instance.init();
    });

    test('creates a record for a first sign in', () async {
      await ProfileService.instance.registerProfileSnapshot(
        scope: "",
        userID: 7,
        email: "someone@example.org",
        isOnline: true,
      );

      final profile = ProfileService.instance.profiles.single;
      expect(profile.scope, isEmpty);
      expect(profile.kind, ProfileKind.online);
      expect(profile.userID, 7);
      expect(profile.email, "someone@example.org");
    });

    test('is idempotent and preserves the label', () async {
      await ProfileService.instance.registerProfileSnapshot(
        scope: "acct_1.",
        isOnline: false,
      );
      await ProfileService.instance.rename("acct_1.", "Work laptop");

      await ProfileService.instance.registerProfileSnapshot(
        scope: "acct_1.",
        userID: 3,
        email: "someone@example.org",
        isOnline: true,
      );

      final profile = ProfileService.instance.profiles.single;
      expect(ProfileService.instance.profiles, hasLength(1));
      expect(profile.label, "Work laptop");
      expect(profile.kind, ProfileKind.online);
      expect(profile.userID, 3);
    });
  });

  group('the profile cap', () {
    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    test('allows adding until the maximum is reached', () async {
      SharedPreferences.setMockInitialValues({
        "profilesV1": List.generate(
          ProfileService.maxProfiles - 1,
          (i) => json.encode(
            Profile(scope: "acct_$i.", kind: ProfileKind.online).toMap(),
          ),
        ),
        "profilesActiveScope": "acct_0.",
        for (var i = 0; i < ProfileService.maxProfiles - 1; i++)
          "acct_$i.token": "token-$i",
      });
      await ProfileService.instance.init();

      expect(ProfileService.instance.canAddProfile, isTrue);
    });

    test('refuses to begin an add once full', () async {
      SharedPreferences.setMockInitialValues({
        "profilesV1": List.generate(
          ProfileService.maxProfiles,
          (i) => json.encode(
            Profile(scope: "acct_$i.", kind: ProfileKind.online).toMap(),
          ),
        ),
        "profilesActiveScope": "acct_0.",
        for (var i = 0; i < ProfileService.maxProfiles; i++)
          "acct_$i.token": "token-$i",
      });
      await ProfileService.instance.init();

      expect(ProfileService.instance.canAddProfile, isFalse);
      expect(ProfileService.instance.beginAdd(), throwsStateError);
      // The rejected attempt must not have consumed a scope or a profile slot.
      expect(
        ProfileService.instance.profiles,
        hasLength(ProfileService.maxProfiles),
      );
    });
  });

  group('committing an add', () {
    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({
        "profilesV1": <String>[],
        "profilesActiveScope": "",
      });
      await ProfileService.instance.init();
    });

    test('renaming a vault persists and can be cleared', () async {
      await ProfileService.instance.upsert(
        const Profile(scope: "acct_1.", kind: ProfileKind.offline),
      );

      await ProfileService.instance.rename("acct_1.", "  Work laptop  ");
      expect(ProfileService.instance.profiles.single.label, "Work laptop");

      await ProfileService.instance.rename("acct_1.", "   ");
      expect(ProfileService.instance.profiles.single.label, isNull);
    });

    test('is idempotent for the same scope', () async {
      // The online path commits from the sign in listener and the offline path
      // commits from the caller. A second call must not re-run duplicate
      // detection and discard the vault it just registered.
      await ProfileService.instance.upsert(
        const Profile(scope: "acct_1.", kind: ProfileKind.offline),
      );

      final result = await ProfileService.instance.commitAdd("acct_1.");

      expect(result, isNull);
      expect(ProfileService.instance.profiles, hasLength(1));
      expect(ProfileService.instance.profiles.single.scope, "acct_1.");
      expect(ProfileService.instance.activeScope, "acct_1.");
    });
  });

  group('Profile', () {
    test('survives a serialization round trip', () {
      const profile = Profile(
        scope: "acct_1.",
        kind: ProfileKind.online,
        userID: 42,
        email: "someone@example.org",
      );

      final restored = Profile.fromMap(profile.toMap());

      expect(restored.scope, profile.scope);
      expect(restored.kind, profile.kind);
      expect(restored.userID, profile.userID);
      expect(restored.email, profile.email);
    });

    test('falls back through label, email, then the offline name', () {
      const named = Profile(
        scope: "acct_1.",
        kind: ProfileKind.offline,
        label: "Work laptop",
      );
      const online = Profile(
        scope: "acct_2.",
        kind: ProfileKind.online,
        email: "someone@example.org",
      );
      const bare = Profile(scope: "acct_3.", kind: ProfileKind.offline);
      const blank = Profile(
        scope: "acct_4.",
        kind: ProfileKind.offline,
        label: "   ",
      );

      expect(named.displayName("Offline vault"), "Work laptop");
      expect(online.displayName("Offline vault"), "someone@example.org");
      expect(bare.displayName("Offline vault"), "Offline vault");
      expect(blank.displayName("Offline vault"), "Offline vault");
    });

    test('a label survives a serialization round trip', () {
      const profile = Profile(
        scope: "acct_1.",
        kind: ProfileKind.offline,
        label: "Work laptop",
      );

      expect(Profile.fromMap(profile.toMap()).label, "Work laptop");
    });

    test('the kind survives a round trip', () {
      const online = Profile(scope: "", kind: ProfileKind.online);
      const offline = Profile(scope: "acct_1.", kind: ProfileKind.offline);

      expect(online.isOffline, isFalse);
      expect(offline.isOffline, isTrue);
    });
  });
}
