import 'dart:async';

import 'package:ente_contacts/src/models/contact_record.dart';
import 'package:ente_contacts/src/models/contacts_session.dart';
import 'package:ente_contacts/src/service/contacts_service.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ContactsDisplayService {
  ContactsDisplayService._privateConstructor();

  static final ContactsDisplayService instance =
      ContactsDisplayService._privateConstructor();

  static const Duration _profilePictureFailureTtl = Duration(minutes: 1);

  final Logger _logger = Logger('ContactsDisplayService');
  final ValueNotifier<int> _changes = ValueNotifier<int>(0);
  final Map<int, ContactRecord> _contactsByUserId = {};
  final Map<String, ContactRecord> _contactsByNormalizedEmail = {};
  final Map<int, String?> _normalizedEmailByUserId = {};
  final Map<int, Uint8List?> _profilePictureBytesByUserId = {};
  final Set<int> _resolvedProfilePictureUserIds = {};
  final Map<int, Future<Uint8List?>> _profilePictureLoadsByUserId = {};
  final Map<int, DateTime> _profilePictureFailureUntilByUserId = {};

  SharedPreferences? _preferences;
  ContactsService Function()? _contactsServiceFactory;
  ContactsService? _contacts;
  ContactsSession? _session;
  String? _sessionKey;
  String? _sessionAuthToken;
  Future<void>? _readyFuture;
  bool _hasHydratedCache = false;
  int _sessionGeneration = 0;

  ValueListenable<int> get changes => _changes;

  bool get hasHydratedCache => _hasHydratedCache;

  void init({
    required SharedPreferences preferences,
    ContactsService? contactsService,
    ContactsService Function()? contactsServiceFactory,
  }) {
    _preferences = preferences;
    _contactsServiceFactory =
        contactsServiceFactory ??
        (contactsService != null ? () => contactsService : null);
    _contacts ??= contactsService;
  }

  Future<void> ensureReady(ContactsSession session) async {
    final sessionKey = _buildSessionKey(session);
    if (_readyFuture != null && _sessionKey == sessionKey) {
      final contacts = _requireContacts();
      await _readyFuture;
      if (_sessionAuthToken != session.authToken) {
        await contacts.updateAuthToken(session.authToken);
        _sessionAuthToken = session.authToken;
        _session = session;
      }
      return;
    }

    if (_sessionKey != sessionKey) {
      _sessionGeneration += 1;
      _clearCachedState(notify: true);
    }
    _contacts ??= _newContactsService();
    final currentContacts = _requireContacts();

    _session = session;
    _sessionKey = sessionKey;
    _sessionAuthToken = session.authToken;

    late final Future<void> readyFuture;
    final generation = _sessionGeneration;
    readyFuture = _openAndSync(currentContacts, session, generation).catchError(
      (Object error, StackTrace stackTrace) {
        if (identical(_readyFuture, readyFuture)) {
          _readyFuture = null;
        }
        _logger.warning(
          'Failed to hydrate shared contacts display cache',
          error,
          stackTrace,
        );
        throw error;
      },
    );
    _readyFuture = readyFuture;
    await readyFuture;
  }

  Future<void> updateAuthToken(String authToken) async {
    final contacts = _contacts;
    final session = _session;
    if (contacts == null || session == null) {
      return;
    }
    if (_sessionAuthToken == authToken) {
      return;
    }
    await contacts.updateAuthToken(authToken);
    _sessionAuthToken = authToken;
    _session = ContactsSession(
      baseUrl: session.baseUrl,
      authToken: authToken,
      userId: session.userId,
      accountKey: session.accountKey,
      accountKeyProvider: session.accountKeyProvider,
      userAgent: session.userAgent,
      clientPackage: session.clientPackage,
      clientVersion: session.clientVersion,
    );
  }

  Future<void> resetLocalState() async {
    final contacts = _contacts;
    _sessionGeneration += 1;
    _clearCachedState(notify: true);
    await contacts?.resetLocalState();
  }

  ContactRecord? getCachedContact({int? contactUserId, String? email}) {
    final cachedByUserId = _contactByUserIdOrNull(contactUserId);
    if (cachedByUserId != null) {
      return cachedByUserId;
    }
    return _contactByEmailOrNull(email);
  }

  String? getCachedSavedName({int? contactUserId, String? email}) {
    final savedName = getCachedContact(
      contactUserId: contactUserId,
      email: email,
    )?.data?.name;
    if (savedName == null) {
      return null;
    }
    final trimmed = savedName.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? getCachedResolvedEmail({int? contactUserId, String? email}) {
    final resolved = getCachedContact(
      contactUserId: contactUserId,
      email: email,
    )?.email;
    if (resolved == null) {
      return null;
    }
    final trimmed = resolved.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Uint8List? getCachedProfilePictureBytes({int? contactUserId, String? email}) {
    final resolvedUserId = _resolvedContactUserId(
      contactUserId: contactUserId,
      email: email,
    );
    if (resolvedUserId == null ||
        !_resolvedProfilePictureUserIds.contains(resolvedUserId)) {
      return null;
    }
    return _profilePictureBytesByUserId[resolvedUserId];
  }

  bool hasResolvedProfilePicture({int? contactUserId, String? email}) {
    final resolvedUserId = _resolvedContactUserId(
      contactUserId: contactUserId,
      email: email,
    );
    return resolvedUserId != null &&
        _resolvedProfilePictureUserIds.contains(resolvedUserId);
  }

  Future<Uint8List?> getProfilePictureBytes({
    int? contactUserId,
    String? email,
  }) async {
    final contact = getCachedContact(
      contactUserId: contactUserId,
      email: email,
    );
    if (contact == null) {
      if (_hasHydratedCache) {
        final resolvedUserId = contactUserId;
        if (resolvedUserId != null) {
          _profilePictureBytesByUserId.remove(resolvedUserId);
          _resolvedProfilePictureUserIds.add(resolvedUserId);
        }
      }
      return null;
    }

    final contactUserIdValue = contact.contactUserId;
    if (_resolvedProfilePictureUserIds.contains(contactUserIdValue)) {
      return _profilePictureBytesByUserId[contactUserIdValue];
    }

    final failureUntil =
        _profilePictureFailureUntilByUserId[contactUserIdValue];
    final now = DateTime.now();
    if (failureUntil != null && failureUntil.isAfter(now)) {
      return null;
    }

    final inflightLoad = _profilePictureLoadsByUserId[contactUserIdValue];
    if (inflightLoad != null) {
      return inflightLoad;
    }

    final load = _loadProfilePictureBytes(contact);
    _profilePictureLoadsByUserId[contactUserIdValue] = load;
    return load.whenComplete(() {
      _profilePictureLoadsByUserId.remove(contactUserIdValue);
    });
  }

  @visibleForTesting
  Future<void> debugReset({bool clearLocalState = true}) async {
    final contacts = _contacts;
    if (clearLocalState) {
      await contacts?.resetLocalState();
    }
    _clearCachedState(notify: false);
    if (_changes.value != 0) {
      _changes.value = 0;
    }
  }

  @visibleForTesting
  void debugHydrateContacts(
    List<ContactRecord> contacts, {
    bool notify = true,
  }) {
    final changedUserIds = _cacheContacts(contacts);
    _hasHydratedCache = true;
    if (notify && changedUserIds.isNotEmpty) {
      _notifyChanged();
    }
  }

  @visibleForTesting
  void debugSetProfilePictureBytes({
    required int contactUserId,
    Uint8List? bytes,
    bool notify = true,
  }) {
    if (bytes == null) {
      _profilePictureBytesByUserId.remove(contactUserId);
    } else {
      _profilePictureBytesByUserId[contactUserId] = bytes;
    }
    _resolvedProfilePictureUserIds.add(contactUserId);
    _profilePictureFailureUntilByUserId.remove(contactUserId);
    _profilePictureLoadsByUserId.remove(contactUserId);
    if (notify) {
      _notifyChanged();
    }
  }

  Future<void> _openAndSync(
    ContactsService contacts,
    ContactsSession session,
    int generation,
  ) async {
    await contacts.open(session);
    if (!_isSessionGenerationCurrent(generation, session)) {
      return;
    }

    final localContacts = await contacts.getContacts();
    if (!_isSessionGenerationCurrent(generation, session)) {
      return;
    }
    final localChanged = _cacheContacts(localContacts);
    _hasHydratedCache = true;
    if (localChanged.isNotEmpty) {
      _notifyChanged();
    }

    try {
      final diff = await contacts.sync();
      if (!_isSessionGenerationCurrent(generation, session)) {
        return;
      }
      final diffChanged = _cacheContacts(diff, invalidateProfilePictures: true);
      if (diffChanged.isNotEmpty) {
        _notifyChanged();
      }
    } catch (error, stackTrace) {
      if (!_isSessionGenerationCurrent(generation, session)) {
        return;
      }
      _logger.warning(
        'Failed to sync shared contacts display cache after hydrating local cache',
        error,
        stackTrace,
      );
      _readyFuture = null;
    }
  }

  Future<Uint8List?> _loadProfilePictureBytes(ContactRecord contact) async {
    final attachmentId = contact.profilePictureAttachmentId;
    if (attachmentId == null) {
      _profilePictureBytesByUserId.remove(contact.contactUserId);
      _resolvedProfilePictureUserIds.add(contact.contactUserId);
      return null;
    }

    try {
      final bytes = await _requireContacts().getProfilePicture(contact.id);
      final latestContact = _contactsByUserId[contact.contactUserId];
      if (latestContact == null ||
          latestContact.isDeleted ||
          latestContact.id != contact.id ||
          latestContact.profilePictureAttachmentId != attachmentId) {
        return _profilePictureBytesByUserId[contact.contactUserId];
      }
      _profilePictureBytesByUserId[contact.contactUserId] = bytes;
      _resolvedProfilePictureUserIds.add(contact.contactUserId);
      _profilePictureFailureUntilByUserId.remove(contact.contactUserId);
      _notifyChanged();
      return bytes;
    } catch (error, stackTrace) {
      _profilePictureFailureUntilByUserId[contact.contactUserId] =
          DateTime.now().add(_profilePictureFailureTtl);
      _logger.info(
        'Failed to load shared contact profile picture for user ${contact.contactUserId}',
        error,
        stackTrace,
      );
      return null;
    }
  }

  Set<int> _cacheContacts(
    List<ContactRecord> contacts, {
    bool invalidateProfilePictures = false,
  }) {
    final changedUserIds = <int>{};
    for (final contact in contacts) {
      if (_cacheContact(
        contact,
        invalidateProfilePicture: invalidateProfilePictures,
      )) {
        changedUserIds.add(contact.contactUserId);
      }
    }
    return changedUserIds;
  }

  bool _cacheContact(
    ContactRecord contact, {
    required bool invalidateProfilePicture,
  }) {
    final existing = _contactsByUserId[contact.contactUserId];
    final previousEmail = _normalizedEmailByUserId[contact.contactUserId];
    if (previousEmail != null) {
      _contactsByNormalizedEmail.remove(previousEmail);
    }

    if (contact.isDeleted) {
      final wasCached = existing != null;
      _contactsByUserId.remove(contact.contactUserId);
      _normalizedEmailByUserId.remove(contact.contactUserId);
      if (invalidateProfilePicture || wasCached) {
        _invalidateProfilePictureCache(contact.contactUserId);
      }
      return wasCached;
    }

    final normalizedEmail = _normalizeEmail(contact.email);
    if (normalizedEmail != null) {
      _contactsByNormalizedEmail[normalizedEmail] = contact;
    }
    _normalizedEmailByUserId[contact.contactUserId] = normalizedEmail;
    _contactsByUserId[contact.contactUserId] = contact;
    if (invalidateProfilePicture) {
      _invalidateProfilePictureCache(contact.contactUserId);
    }
    return existing != contact;
  }

  ContactRecord? _contactByUserIdOrNull(int? contactUserId) {
    if (contactUserId == null) {
      return null;
    }
    final contact = _contactsByUserId[contactUserId];
    if (contact == null || contact.isDeleted) {
      return null;
    }
    return contact;
  }

  ContactRecord? _contactByEmailOrNull(String? email) {
    final normalizedEmail = _normalizeEmail(email);
    if (normalizedEmail == null) {
      return null;
    }
    final contact = _contactsByNormalizedEmail[normalizedEmail];
    if (contact == null || contact.isDeleted) {
      return null;
    }
    return contact;
  }

  int? _resolvedContactUserId({int? contactUserId, String? email}) {
    return getCachedContact(
      contactUserId: contactUserId,
      email: email,
    )?.contactUserId;
  }

  String _buildSessionKey(ContactsSession session) {
    return '${session.baseUrl}|${session.userId}';
  }

  String? _normalizeEmail(String? email) {
    if (email == null) {
      return null;
    }
    final trimmed = email.trim().toLowerCase();
    return trimmed.isEmpty ? null : trimmed;
  }

  ContactsService _requireContacts() {
    final contacts = _contacts;
    if (contacts == null) {
      throw StateError(
        'ContactsDisplayService.init(preferences: ...) must be called before use',
      );
    }
    return contacts;
  }

  ContactsService _newContactsService() {
    final factory = _contactsServiceFactory;
    if (factory != null) {
      return factory();
    }
    final preferences = _preferences;
    if (preferences == null) {
      throw StateError(
        'ContactsDisplayService.init(preferences: ...) must be called before use',
      );
    }
    return ContactsService(preferences: preferences);
  }

  bool _isSessionGenerationCurrent(int generation, ContactsSession session) {
    return _sessionGeneration == generation &&
        _sessionKey == _buildSessionKey(session);
  }

  void _clearCachedState({required bool notify}) {
    final hadCachedState =
        _contactsByUserId.isNotEmpty ||
        _contactsByNormalizedEmail.isNotEmpty ||
        _profilePictureBytesByUserId.isNotEmpty ||
        _resolvedProfilePictureUserIds.isNotEmpty;
    _contactsByUserId.clear();
    _contactsByNormalizedEmail.clear();
    _normalizedEmailByUserId.clear();
    _profilePictureBytesByUserId.clear();
    _resolvedProfilePictureUserIds.clear();
    _profilePictureLoadsByUserId.clear();
    _profilePictureFailureUntilByUserId.clear();
    _readyFuture = null;
    _contacts = null;
    _session = null;
    _sessionKey = null;
    _sessionAuthToken = null;
    _hasHydratedCache = false;
    if (notify && hadCachedState) {
      _notifyChanged();
    }
  }

  void _invalidateProfilePictureCache(int contactUserId) {
    _profilePictureBytesByUserId.remove(contactUserId);
    _resolvedProfilePictureUserIds.remove(contactUserId);
    _profilePictureLoadsByUserId.remove(contactUserId);
    _profilePictureFailureUntilByUserId.remove(contactUserId);
  }

  void _notifyChanged() {
    _changes.value += 1;
  }
}
