import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:ente_accounts/services/user_service.dart';
import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/models/profile.dart';
import 'package:ente_auth/services/authenticator_service.dart';
import 'package:ente_auth/services/billing_service.dart';
import 'package:ente_auth/services/local_backup_service.dart';
import 'package:ente_auth/store/authenticator_db.dart';
import 'package:ente_auth/store/offline_authenticator_db.dart';
import 'package:ente_auth/utils/directory_utils.dart';
import 'package:ente_configuration/base_configuration.dart';
import 'package:ente_events/event_bus.dart';
import 'package:ente_events/models/signed_in_event.dart';
import 'package:ente_events/models/user_details_changed_event.dart';
import 'package:ente_lock_screen/lock_screen_settings.dart';
import 'package:ente_network/network.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The profile list is app wide state, so it is stored under unprefixed keys.
// Everything an account owns lives under its Profile.scope prefix.
class ProfileService {
  static const maxProfiles = 5;

  static const _profilesKey = "profilesV1";
  static const _activeScopeKey = "profilesActiveScope";
  static const _nextIdKey = "profilesNextId";

  final _logger = Logger((ProfileService).toString());

  ProfileService._privateConstructor();

  static final ProfileService instance = ProfileService._privateConstructor();

  late SharedPreferences _prefs;
  List<Profile> _profiles = const [];
  String _activeScope = "";

  String? _pendingAddReturnScope;
  StreamSubscription<SignedInEvent>? _pendingAddSubscription;
  StreamSubscription<SignedInEvent>? _signedInSubscription;
  StreamSubscription<UserDetailsChangedEvent>? _userDetailsSubscription;
  Future<Profile?>? _commitInFlight;
  bool _rejectedDuplicateAdd = false;

  // The registry is read at build time by the home app bar, the settings
  // header and the switcher, none of which are rebuilt by a change to a
  // profile's own details (an email change, a rename).
  final ValueNotifier<Profile?> activeProfileNotifier = ValueNotifier(null);

  bool consumeRejectedDuplicateAdd() {
    final rejected = _rejectedDuplicateAdd;
    _rejectedDuplicateAdd = false;
    return rejected;
  }

  List<Profile> get profiles => List.unmodifiable(_profiles);

  String get activeScope => _activeScope;

  bool get hasMultipleProfiles => _profiles.length > 1;

  // Whether no account other than [scope] is left for the app lock to guard.
  //
  // Not "is there a single profile": a profile being added is unregistered
  // until commitAdd, so during an add the sole registered profile is another
  // account that is still signed in, and reading that as the last sign out
  // would take the app lock down with the aborted add.
  bool isLastProfile(String scope) =>
      _profiles.every((profile) => profile.scope == scope);

  bool get canAddProfile => _profiles.length < maxProfiles;

  Profile? get activeProfile =>
      _profiles.where((profile) => profile.scope == _activeScope).firstOrNull;

  // Must run before Configuration.init(), which needs the active scope.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final stored = _prefs.getStringList(_profilesKey);
    if (stored == null) {
      await _seedFromLegacyState();
    } else {
      _profiles = stored
          .map((e) => Profile.fromMap(json.decode(e) as Map<String, dynamic>))
          .toList();
      _activeScope = _prefs.getString(_activeScopeKey) ?? "";
      if (_profiles.isEmpty && _hasLegacyAccountData()) {
        _logger.warning("Unregistered legacy account found, re-seeding");
        await _seedFromLegacyState();
      }
      await reconcile();
      if (_profiles.isNotEmpty && activeProfile == null) {
        _logger.warning(
          "Active scope '$_activeScope' is unknown, falling back to the first "
          "profile",
        );
        _activeScope = _profiles.first.scope;
        await _persist();
      }
    }
    // Registers the account for a sign in outside the add flow, in particular
    // the first sign in on a fresh install.
    _signedInSubscription ??= Bus.instance.on<SignedInEvent>().listen((event) {
      unawaited(ensureActiveProfileRegistered());
    });
    // The account's own details can change while it is signed in, and the
    // profile keeps a copy of the email to show. Without this it would keep
    // showing the address the account was registered with.
    _userDetailsSubscription ??= Bus.instance
        .on<UserDetailsChangedEvent>()
        .listen((event) {
          unawaited(ensureActiveProfileRegistered());
        });
    _notifyActiveProfile();
    _logger.info(
      "Loaded ${_profiles.length} profile(s), active '$_activeScope'",
    );
  }

  // Matches reconcile()'s notion of an account that still has data. The
  // encrypted token counts: an account waiting on password re-entry has one
  // but no token yet, and seeding it as nothing would hide the account row
  // (and with it the switcher) for good.
  bool _hasLegacyAccountData() {
    return _prefs.containsKey(BaseConfiguration.tokenKey) ||
        _prefs.containsKey(BaseConfiguration.encryptedTokenKey) ||
        (_prefs.getBool(Configuration.hasOptedForOfflineModeKey) ?? false);
  }

  // Drops records for vaults that have no data left to open. Every logout the
  // app knows about goes through completeLogout(), which removes the record
  // itself; this is the backstop for a path that clears an account without
  // knowing about profiles, so that such a record cannot outlive a restart.
  Future<void> reconcile() async {
    bool hasAccountData(Profile profile) {
      final scope = profile.scope;
      return _prefs.containsKey("$scope${BaseConfiguration.tokenKey}") ||
          _prefs.containsKey("$scope${BaseConfiguration.encryptedTokenKey}") ||
          (_prefs.getBool("$scope${Configuration.hasOptedForOfflineModeKey}") ??
              false);
    }

    final dead = _profiles.where((p) => !hasAccountData(p)).toList();
    if (dead.isEmpty) {
      return;
    }
    _logger.warning("Dropping ${dead.length} profile(s) with no data: $dead");
    _profiles = _profiles.where(hasAccountData).toList();
    if (_profiles.isEmpty) {
      _activeScope = "";
    } else if (activeProfile == null) {
      _activeScope = _profiles.first.scope;
    }
    await _persist();
  }

  // No-ops while an add is in flight: registering there would make commitAdd
  // take its early return and skip the duplicate account check.
  Future<void> ensureActiveProfileRegistered() async {
    if (_pendingAddSubscription != null) {
      return;
    }
    final config = Configuration.instance;
    await registerProfileSnapshot(
      scope: config.scope,
      userID: config.getUserID(),
      email: config.getEmail(),
      isOnline: config.isLoggedIn(),
    );
  }

  // isOnline must come from isLoggedIn(), not hasConfiguredAccount(): during
  // sign up the signed in event fires before the keys exist, and the stricter
  // check would misfile the account as an offline vault.
  Future<void> registerProfileSnapshot({
    required String scope,
    int? userID,
    String? email,
    required bool isOnline,
  }) async {
    final existing = _profiles
        .where((profile) => profile.scope == scope)
        .firstOrNull;
    await upsert(
      Profile(
        scope: scope,
        kind: isOnline ? ProfileKind.online : ProfileKind.offline,
        userID: userID ?? existing?.userID,
        email: email ?? existing?.email,
        label: existing?.label,
      ),
    );
  }

  // The pre-existing account keeps the empty scope, so none of its
  // preferences, secure storage entries or database files need to move.
  Future<void> _seedFromLegacyState() async {
    _activeScope = "";
    // The encrypted token counts too; see _hasLegacyAccountData.
    final hasToken =
        _prefs.containsKey(BaseConfiguration.tokenKey) ||
        _prefs.containsKey(BaseConfiguration.encryptedTokenKey);
    final hasOfflineVault =
        _prefs.getBool(Configuration.hasOptedForOfflineModeKey) ?? false;
    if (hasToken) {
      _profiles = [
        Profile(
          scope: "",
          kind: ProfileKind.online,
          userID: _prefs.getInt(BaseConfiguration.userIDKey),
          email: _prefs.getString(BaseConfiguration.emailKey),
        ),
      ];
    } else if (hasOfflineVault) {
      _profiles = [const Profile(scope: "", kind: ProfileKind.offline)];
    } else {
      _profiles = const [];
    }
    await _persist();
    _logger.info("Seeded profiles from legacy state: $_profiles");
  }

  Future<void> _persist() async {
    await _prefs.setStringList(
      _profilesKey,
      _profiles.map((profile) => json.encode(profile.toMap())).toList(),
    );
    await _prefs.setString(_activeScopeKey, _activeScope);
    _notifyActiveProfile();
  }

  void _notifyActiveProfile() {
    activeProfileNotifier.value = activeProfile;
  }

  // Ids are never reused, so a removed profile's leftover keys can never be
  // picked up by a later one.
  Future<String> _allocateScope() async {
    final id = (_prefs.getInt(_nextIdKey) ?? 1);
    await _prefs.setInt(_nextIdKey, id + 1);
    return "acct_$id.";
  }

  Profile? profileForUser(int userID) =>
      _profiles.where((profile) => profile.userID == userID).firstOrNull;

  Future<void> rename(String scope, String label) async {
    final index = _profiles.indexWhere((profile) => profile.scope == scope);
    if (index == -1) {
      _logger.warning("Cannot rename unknown scope '$scope'");
      return;
    }
    final trimmed = label.trim();
    final updated = [..._profiles];
    final existing = updated[index];
    updated[index] = Profile(
      scope: existing.scope,
      kind: existing.kind,
      userID: existing.userID,
      email: existing.email,
      label: trimmed.isEmpty ? null : trimmed,
    );
    _profiles = updated;
    await _persist();
  }

  Future<void> upsert(Profile profile) async {
    final index = _profiles.indexWhere((other) => other.scope == profile.scope);
    final updated = [..._profiles];
    if (index == -1) {
      updated.add(profile);
    } else {
      updated[index] = profile;
    }
    _profiles = updated;
    await _persist();
  }

  Future<void> switchTo(String scope) async {
    if (scope == _activeScope) return;
    _logger.info("Switching to '$scope'");
    // Persist only once the services point at the new profile, so a failed
    // switch does not leave the stored scope disagreeing with what is read.
    // _applyScope re-points several singletons in turn, so a failure partway
    // has to be undone as well, or the registry would still name the old
    // profile while its databases were open on the new one.
    final previous = _activeScope;
    try {
      await _applyScope(scope);
    } catch (e, s) {
      _logger.severe("Failed to apply '$scope', restoring '$previous'", e, s);
      try {
        await _applyScope(previous);
      } catch (e2, s2) {
        _logger.severe("Failed to restore '$previous'", e2, s2);
      }
      rethrow;
    }
    _activeScope = scope;
    await _persist();
  }

  // Re-points the account scoped services at [scope]. App wide state (lock
  // screen, theme, locale, general preferences) is deliberately left alone.
  Future<void> _applyScope(String scope) async {
    // Stops a sync from writing the outgoing account's entities into the
    // incoming account's database.
    await AuthenticatorService.instance.suspendSync();
    try {
      await AuthenticatorDB.instance.setScope(scope);
      await OfflineAuthenticatorDB.instance.setScope(scope);
      await Configuration.instance.setScope(scope);
      // Billing plans are per account, and the endpoint may differ.
      BillingService.instance.clearCache();
      await Network.instance.init(Configuration.instance);
      await AuthenticatorService.instance.init();
      await LocalBackupService.instance.init(
        hasOptedForOfflineMode: Configuration.instance.hasOptedForOfflineMode(),
      );
      // Process wide, and otherwise only written by the sign in flow, so
      // without this it keeps showing the previous profile's email.
      UserService.instance.emailValueNotifier.value = Configuration.instance
          .getEmail();
    } finally {
      AuthenticatorService.instance.resumeSync();
    }
  }

  // Returns the scope the sign in flow should run against. The caller must
  // follow up with commitAdd() or abortAdd(); until then the new scope is
  // active but unregistered, so an interrupted sign in leaves nothing behind.
  Future<String> beginAdd() async {
    if (!canAddProfile) {
      throw StateError("At most $maxProfiles profiles are supported");
    }
    _rejectedDuplicateAdd = false;
    final scope = await _allocateScope();
    _logger.info("Beginning add of a profile at '$scope'");
    _pendingAddReturnScope = _activeScope;
    // Undone on failure for the same reason as in switchTo(): a half applied
    // scope leaves the registry naming one profile while the databases are
    // open on another, and nothing here has been registered to abort against.
    try {
      await _applyScope(scope);
    } catch (e, s) {
      _logger.severe(
        "Failed to apply '$scope', restoring '$_activeScope'",
        e,
        s,
      );
      _pendingAddReturnScope = null;
      try {
        await _applyScope(_activeScope);
      } catch (e2, s2) {
        _logger.severe("Failed to restore '$_activeScope'", e2, s2);
      }
      rethrow;
    }
    // The sign in flow navigates on its own across several pages, so watch for
    // it completing rather than awaiting it.
    await _pendingAddSubscription?.cancel();
    _pendingAddSubscription = Bus.instance.on<SignedInEvent>().listen((event) {
      unawaited(_pendingAddSubscription?.cancel());
      _pendingAddSubscription = null;
      unawaited(commitAdd(scope));
    });
    return scope;
  }

  // Returns the profile already signed in as this user, if any, in which case
  // nothing is added and the caller should switch to it instead.
  //
  // The sign in listener in beginAdd() and the add page both commit, and the
  // page's "is it registered yet" check can run while the listener's commit is
  // still mid flight. Sharing the one future keeps the two from each running
  // the duplicate check against a registry that does not hold the scope yet,
  // which would abort the account just added.
  Future<Profile?> commitAdd(String scope) {
    return _commitInFlight ??= _commitAdd(
      scope,
    ).whenComplete(() => _commitInFlight = null);
  }

  Future<Profile?> _commitAdd(String scope) async {
    await _pendingAddSubscription?.cancel();
    _pendingAddSubscription = null;
    // Idempotent: the online path commits from the sign in listener and the
    // offline path from the caller, and both can be live at once. A second
    // call must not re-run the duplicate check against the profile just added.
    if (_profiles.any((profile) => profile.scope == scope)) {
      _pendingAddReturnScope = null;
      if (_activeScope != scope) {
        _activeScope = scope;
        await _persist();
      }
      return null;
    }
    final config = Configuration.instance;
    final userID = config.getUserID();
    final existing = userID == null ? null : profileForUser(userID);
    if (existing != null) {
      _logger.info("$existing is already signed in, discarding '$scope'");
      _rejectedDuplicateAdd = true;
      // The sign in that got us here was a real one, so the server issued a
      // session for it. Throwing the token away locally would leave that
      // session live and listed under the account's active sessions.
      await _endSessionForRejectedAdd();
      await abortAdd(scope);
      return existing;
    }
    await upsert(
      Profile(
        scope: scope,
        kind: config.isLoggedIn() ? ProfileKind.online : ProfileKind.offline,
        userID: userID,
        email: config.getEmail(),
      ),
    );
    _pendingAddReturnScope = null;
    _activeScope = scope;
    await _persist();
    return null;
  }

  // Best effort: the account is unreachable from the app either way, so a
  // failure here must not stop the scope from being handed back.
  Future<void> _endSessionForRejectedAdd() async {
    try {
      await Network.instance.enteDio.post("/users/logout");
    } catch (e, s) {
      _logger.warning("Failed to end the rejected add's session", e, s);
    }
  }

  Future<void> abortAdd(String scope) async {
    _logger.info("Aborting add of '$scope'");
    await _pendingAddSubscription?.cancel();
    _pendingAddSubscription = null;
    final returnScope = _pendingAddReturnScope ?? "";
    _pendingAddReturnScope = null;
    _profiles = _profiles.where((profile) => profile.scope != scope).toList();
    _activeScope = returnScope;
    await _persist();
    // Re-point everything at the surviving profile before erasing. The
    // databases are singletons, so deleting first leaves a window where a sync
    // or a page load reopens the file that was just removed. Erasing happens
    // even if that fails: the record is already gone, so nothing would ever
    // come back for this scope's keys and database files.
    try {
      await _applyScope(returnScope);
    } finally {
      await discard(scope);
    }
  }

  // Returns false when that was the last profile, so the caller knows to send
  // the user back to onboarding.
  Future<bool> removeActive() async {
    final scope = _activeScope;
    // From the profile record, not the configuration: a logout has usually
    // cleared the token by now, so hasConfiguredAccount() would report every
    // profile as an offline one.
    if (activeProfile?.isOffline ?? false) {
      await Configuration.instance.clearOfflineAccount();
      // Removing a vault fires no SignedOutEvent, so the listener that
      // normally clears this never runs. discard() would cover a prefixed
      // scope, but the legacy scope's keys carry no prefix to match on, so it
      // would otherwise be inherited by the next account at that scope.
      await Configuration.instance.clearBackupPassword();
      if (scope.isEmpty) {
        // discard() cannot delete the legacy scope's database files, since a
        // future account at the same scope would reuse those names, so empty
        // the codes out instead of leaving them for it to find.
        await OfflineAuthenticatorDB.instance.clearTable();
      }
    }
    _profiles = _profiles.where((profile) => profile.scope != scope).toList();
    _activeScope = _profiles.isEmpty ? "" : _profiles.first.scope;
    await _persist();
    if (_profiles.isEmpty) {
      // The lock guards the app, so it only goes once nothing is left to
      // guard. Idempotent for an online logout, where the SignedOutEvent
      // listener has already done this; the offline path has no such event.
      await LockScreenSettings.instance.clearAppLockOnSignOut();
    }
    // Re-point before erasing; see the note in abortAdd.
    try {
      await _applyScope(_activeScope);
    } finally {
      await discard(scope);
    }
    return _profiles.isNotEmpty;
  }

  // A sign out that cleared the account without going through
  // completeLogout(), namely the sign in flow's own "change email" paths.
  // Drops the record for the scope that was cleared, so the registry cannot
  // outlive the account's data.
  //
  // Deliberately not removeActive(): the caller is a sign in flow that means
  // to carry on and sign in again, and switching to a surviving profile would
  // drop the user into someone else's vault instead of the email screen they
  // asked for. The scope stays active but unregistered, exactly as during an
  // add, so signing back in lands here and re-registers it; backing out
  // instead leaves an unknown active scope, which init() falls back from.
  //
  // Configuration.logout() has already erased this scope's preferences, keys
  // and entities, so there is nothing further to discard.
  Future<void> handleExternalLogout() async {
    final scope = Configuration.instance.scope;
    // An unregistered scope is a profile mid add: the add flow hands it back
    // through abortAdd, and dropping a record here would target the wrong
    // profile since _activeScope still names the one the user was on.
    if (scope != _activeScope ||
        !_profiles.any((profile) => profile.scope == scope)) {
      return;
    }
    _logger.info("Dropping '$scope' after a sign out taken outside the app");
    _profiles = _profiles.where((profile) => profile.scope != scope).toList();
    await _persist();
  }

  // Erases the preferences, keychain entries and database files [scope] owns.
  // Callers must already have made a different profile active.
  Future<void> discard(String scope) async {
    if (_profiles.any((profile) => profile.scope == scope)) {
      _profiles = _profiles.where((profile) => profile.scope != scope).toList();
      await _persist();
    }
    if (scope.isEmpty) {
      // Its keys carry no prefix, so there is nothing safe to match on.
      // Configuration.logout() already clears them wholesale.
      _logger.info("Skipping key cleanup for the legacy scope");
      return;
    }
    for (final key in _prefs.getKeys().where((key) => key.startsWith(scope))) {
      await _prefs.remove(key);
    }
    await Configuration.instance.clearSecureStorageForScope(scope);
    await _deleteDatabases(scope);
  }

  Future<void> _deleteDatabases(String scope) async {
    final names = [
      AuthenticatorDB.databaseNameForScope(scope),
      OfflineAuthenticatorDB.databaseNameForScope(scope),
    ];
    for (final name in names) {
      try {
        final String path;
        if (Platform.isWindows || Platform.isLinux) {
          path = await DirectoryUtils.getDatabasePath(name);
        } else {
          final directory = Platform.isMacOS
              ? await getApplicationSupportDirectory()
              : await getApplicationDocumentsDirectory();
          path = p.join(directory.path, name);
        }
        for (final suffix in const ["", "-wal", "-shm"]) {
          final file = File("$path$suffix");
          if (await file.exists()) {
            await file.delete();
          }
        }
      } catch (e, s) {
        _logger.severe("Failed to delete database $name", e, s);
      }
    }
  }
}
