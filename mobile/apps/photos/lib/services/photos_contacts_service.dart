import "package:ente_contacts/contacts.dart" as contacts;
import "package:flutter/foundation.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/contacts_changed_event.dart";
import "package:photos/events/user_logged_out_event.dart";
import "package:photos/service_locator.dart";
import "package:photos/utils/contact_string_util.dart";

class PhotosContactsService {
  PhotosContactsService._privateConstructor()
    : _contactsServiceFactory = (() => contacts.ContactsService(
        preferences: ServiceLocator.instance.prefs,
      )) {
    _attachSessionResetListeners();
  }

  @visibleForTesting
  PhotosContactsService.forTesting({
    contacts.ContactsService? contactsService,
    contacts.ContactsService Function()? contactsServiceFactory,
  }) : _contacts = contactsService,
       _contactsServiceFactory =
           contactsServiceFactory ??
           (contactsService != null ? () => contactsService : null) {
    _attachSessionResetListeners();
  }

  static final PhotosContactsService instance =
      PhotosContactsService._privateConstructor();

  final contacts.ContactsService Function()? _contactsServiceFactory;
  final _logger = Logger("PhotosContactsService");
  // Deleted records evict entries; these indexes contain active contacts only.
  final Map<int, contacts.ContactRecord> _activeContactsByUserId = {};
  final Map<String, contacts.ContactRecord> _activeContactsByNormalizedEmail =
      {};
  final Map<int, Uint8List?> _profilePictureBytesByUserId = {};
  final Set<int> _resolvedProfilePictureUserIds = {};
  final Map<int, Future<Uint8List?>> _profilePictureLoadsByUserId = {};

  contacts.ContactsService? _contacts;
  Future<void>? _readyFuture;
  String? _sessionKey;
  String? _sessionAuthToken;
  bool _hasHydratedCache = false;
  int _sessionGeneration = 0;

  bool get hasHydratedCache => _hasHydratedCache;

  bool get needsWarmup => !_hasHydratedCache || _readyFuture == null;

  Future<void> ensureReady() async {
    final session = _buildSession();
    if (session == null) {
      _sessionGeneration += 1;
      _resetSessionState(notify: true);
      return;
    }
    final sessionKey = _buildSessionKey(session);
    if (_readyFuture != null && _sessionKey == sessionKey) {
      final contacts = _requireContacts();
      await _readyFuture;
      if (_sessionAuthToken != session.authToken) {
        await contacts.updateAuthToken(session.authToken);
        _sessionAuthToken = session.authToken;
      }
      return;
    }
    if (_sessionKey != sessionKey) {
      _sessionGeneration += 1;
      _resetSessionState(notify: true);
    }
    _contacts ??= _newContactsService();
    final currentContacts = _requireContacts();
    _sessionKey = sessionKey;
    _sessionAuthToken = session.authToken;
    late final Future<void> readyFuture;
    final generation = _sessionGeneration;
    readyFuture = _openAndSync(currentContacts, session, generation).catchError(
      (Object error, StackTrace stackTrace) {
        if (identical(_readyFuture, readyFuture)) {
          _readyFuture = null;
        }
        throw error;
      },
    );
    _readyFuture = readyFuture;
    return readyFuture;
  }

  Future<contacts.ContactRecord?> getContact({
    int? contactUserId,
    String? email,
  }) async {
    final cached = getCachedContact(contactUserId: contactUserId, email: email);
    if (cached != null) {
      return cached;
    }
    return _runReadSafely(() async {
      await ensureReady();
      final hydratedCached = getCachedContact(
        contactUserId: contactUserId,
        email: email,
      );
      if (hydratedCached != null) {
        return hydratedCached;
      }
      if (contactUserId == null) {
        return null;
      }
      final contacts = _activeContactsOrNull();
      if (contacts == null) {
        return null;
      }
      final contact = await contacts.getContactByUserId(contactUserId);
      if (contact != null) {
        _cacheContact(contact);
      }
      return getCachedContact(contactUserId: contactUserId, email: email);
    }, description: "load contact for user $contactUserId");
  }

  contacts.ContactRecord? getCachedContact({
    int? contactUserId,
    String? email,
  }) {
    if (_sessionKey == null) {
      return null;
    }
    if (contactUserId != null) {
      return _activeContactsByUserId[contactUserId];
    }
    final normalizedEmail = normalizeContactLinkEmail(email);
    return normalizedEmail == null
        ? null
        : _activeContactsByNormalizedEmail[normalizedEmail];
  }

  List<contacts.ContactRecord> getCachedContacts() {
    if (_sessionKey == null) {
      return const [];
    }
    return List.unmodifiable(_activeContactsByUserId.values);
  }

  String? getCachedSavedName({int? contactUserId, String? email}) {
    return trimToNull(
      getCachedContact(contactUserId: contactUserId, email: email)?.data?.name,
    );
  }

  String? getCachedResolvedEmail({int? contactUserId, String? email}) {
    return trimToNull(
      getCachedContact(contactUserId: contactUserId, email: email)?.email,
    );
  }

  Uint8List? getCachedProfilePictureBytesByUserId(int? contactUserId) {
    if (!hasResolvedProfilePictureByUserId(contactUserId)) {
      return null;
    }
    return _profilePictureBytesByUserId[contactUserId!];
  }

  bool hasResolvedProfilePictureByUserId(int? contactUserId) {
    return contactUserId != null &&
        _sessionKey != null &&
        _resolvedProfilePictureUserIds.contains(contactUserId);
  }

  Future<Uint8List?> getProfilePictureBytesByUserId(int? contactUserId) async {
    if (contactUserId == null) {
      return null;
    }
    if (_sessionKey == null) {
      return null;
    }
    if (hasResolvedProfilePictureByUserId(contactUserId)) {
      return _profilePictureBytesByUserId[contactUserId];
    }
    final contact = await getContact(contactUserId: contactUserId);
    if (contact == null) {
      if (_hasHydratedCache) {
        _profilePictureBytesByUserId.remove(contactUserId);
        _resolvedProfilePictureUserIds.add(contactUserId);
      }
      return null;
    }
    if (_resolvedProfilePictureUserIds.contains(contactUserId)) {
      return _profilePictureBytesByUserId[contactUserId];
    }
    final inflightLoad = _profilePictureLoadsByUserId[contactUserId];
    if (inflightLoad != null) {
      return inflightLoad;
    }
    final load = _loadProfilePictureBytes(contact);
    _profilePictureLoadsByUserId[contactUserId] = load;
    return load.whenComplete(() {
      _profilePictureLoadsByUserId.remove(contactUserId);
    });
  }

  Future<Uint8List?> _loadProfilePictureBytes(
    contacts.ContactRecord contact,
  ) async {
    final contactUserId = contact.contactUserId;
    final attachmentId = contact.profilePictureAttachmentId;
    if (attachmentId == null) {
      _profilePictureBytesByUserId.remove(contactUserId);
      _resolvedProfilePictureUserIds.add(contactUserId);
      return null;
    }
    final contactId = contact.id;
    try {
      final bytes = await _requireContacts().getProfilePicture(contactId);
      final latestContact = _activeContactsByUserId[contactUserId];
      if (latestContact == null ||
          latestContact.isDeleted ||
          latestContact.id != contactId ||
          latestContact.profilePictureAttachmentId != attachmentId) {
        return _profilePictureBytesByUserId[contactUserId];
      }
      _profilePictureBytesByUserId[contactUserId] = bytes;
      _resolvedProfilePictureUserIds.add(contactUserId);
      return bytes;
    } catch (e, s) {
      _logger.warning(
        "Failed to load contact profile picture for user $contactUserId",
        e,
        s,
      );
      return null;
    }
  }

  Future<contacts.ContactRecord> createOrUpdateContact({
    required int contactUserId,
    required String name,
  }) async {
    final contactsService = await _ensureReadyForWrite();
    final trimmedName = name.trim();
    final existing = await contactsService.getContactByUserId(
      contactUserId,
      includeDeleted: true,
    );
    final data = contacts.ContactData(
      contactUserId: contactUserId,
      name: trimmedName,
    );
    final contact = existing == null
        ? await contactsService.createContact(data)
        : await contactsService.updateContact(existing.id, data);
    _cacheContact(contact);
    _notifyChanged(contact);
    return contact;
  }

  Future<contacts.ContactRecord> setProfilePicture({
    required String contactId,
    required Uint8List bytes,
  }) async {
    final contactsService = await _ensureReadyForWrite();
    final contact = await contactsService.setProfilePicture(contactId, bytes);
    _cacheContact(contact);
    _profilePictureBytesByUserId[contact.contactUserId] = bytes;
    _resolvedProfilePictureUserIds.add(contact.contactUserId);
    _notifyChanged(contact);
    return contact;
  }

  Future<contacts.ContactRecord> deleteProfilePicture({
    required String contactId,
  }) async {
    final contactsService = await _ensureReadyForWrite();
    final contact = await contactsService.deleteProfilePicture(contactId);
    _cacheContact(contact);
    _profilePictureBytesByUserId.remove(contact.contactUserId);
    _resolvedProfilePictureUserIds.add(contact.contactUserId);
    _notifyChanged(contact);
    return contact;
  }

  @visibleForTesting
  Future<void> debugOpenAndSync(contacts.ContactsSession session) async {
    final sessionKey = _buildSessionKey(session);
    if (_sessionKey != sessionKey) {
      _sessionGeneration += 1;
      _resetSessionState(notify: false);
    }
    _contacts ??= _newContactsService();
    final currentContacts = _requireContacts();
    _sessionKey = _buildSessionKey(session);
    _sessionAuthToken = session.authToken;
    await _openAndSync(currentContacts, session, _sessionGeneration);
  }

  @visibleForTesting
  void debugHydrateContacts(
    List<contacts.ContactRecord> contacts, {
    bool markHydrated = false,
  }) {
    for (final contact in contacts) {
      _cacheContact(contact);
    }
    if (markHydrated) {
      _hasHydratedCache = true;
    }
  }

  @visibleForTesting
  void debugReset({bool notify = false}) {
    _resetSessionState(notify: notify);
  }

  contacts.ContactsSession? _buildSession() {
    final config = Configuration.instance;
    final userId = config.getUserID();
    final accountKey = config.getKey();
    final token = config.getToken();
    if (token == null || userId == null || accountKey == null) {
      return null;
    }
    final packageInfo = ServiceLocator.instance.packageInfo;
    return contacts.ContactsSession(
      baseUrl: endpointConfig.endpoint,
      authToken: token,
      userId: userId,
      accountKey: accountKey,
      clientPackage: packageInfo.packageName,
      clientVersion: packageInfo.version,
    );
  }

  String _buildSessionKey(contacts.ContactsSession session) {
    return "${session.baseUrl}|${session.userId}";
  }

  Future<void> _openAndSync(
    contacts.ContactsService contactsService,
    contacts.ContactsSession session,
    int generation,
  ) async {
    await contactsService.open(session);
    if (!_isSessionGenerationCurrent(generation, session)) {
      return;
    }

    final cachedUserIdsBeforeHydration = _activeContactsByUserId.keys.toSet();
    final localContacts = await contactsService.getContacts();
    if (!_isSessionGenerationCurrent(generation, session)) {
      return;
    }
    for (final contact in localContacts) {
      _cacheContact(contact);
    }
    _hasHydratedCache = true;
    final newlyHydratedLocalUserIds = localContacts
        .map((contact) => contact.contactUserId)
        .where((userId) => !cachedUserIdsBeforeHydration.contains(userId))
        .toSet();
    final changedUserIds = <int>{...newlyHydratedLocalUserIds};
    var shouldRetrySync = false;
    try {
      final contactsDiff = await contactsService.sync();
      if (!_isSessionGenerationCurrent(generation, session)) {
        return;
      }
      for (final contact in contactsDiff) {
        _invalidateProfilePictureCache(contact.contactUserId);
        _cacheContact(contact);
      }
      changedUserIds.addAll(
        contactsDiff.map((contact) => contact.contactUserId),
      );
    } catch (e, s) {
      if (!_isSessionGenerationCurrent(generation, session)) {
        return;
      }
      shouldRetrySync = true;
      _logger.warning(
        "Failed to sync contacts after hydrating local cache",
        e,
        s,
      );
    }
    if (changedUserIds.isNotEmpty) {
      _notifyContactsChanged(changedUserIds);
    }
    if (shouldRetrySync && _sessionKey == _buildSessionKey(session)) {
      _readyFuture = null;
    }
  }

  bool _isSessionGenerationCurrent(
    int generation,
    contacts.ContactsSession session,
  ) {
    return _sessionGeneration == generation &&
        _sessionKey == _buildSessionKey(session);
  }

  void _notifyChanged(contacts.ContactRecord contact) {
    _notifyContactsChanged({contact.contactUserId});
  }

  void _notifyContactsChanged(Set<int>? contactUserIds) {
    Bus.instance.fire(ContactsChangedEvent(contactUserIds: contactUserIds));
  }

  Future<T?> _runReadSafely<T>(
    Future<T?> Function() task, {
    required String description,
  }) async {
    try {
      return await task();
    } on StateError catch (e, s) {
      if (_isRustInitializationError(e)) {
        _logger.warning(
          "Contacts integration unavailable while Rust bindings are not initialized during $description. Photos initializes EntePhotosRust in main.dart, but ente_contacts calls into package:ente_rust.",
          e,
          s,
        );
        return null;
      }
      if (_isContactsDatabaseNotConfiguredError(e)) {
        _logger.warning(
          "Contacts integration unavailable while contacts are disabled or not initialized during $description",
          e,
          s,
        );
        return null;
      }
      rethrow;
    } catch (e, s) {
      _logger.warning("Failed to $description", e, s);
      return null;
    }
  }

  bool _isRustInitializationError(StateError error) {
    return error.message.contains(
      "flutter_rust_bridge has not been initialized",
    );
  }

  bool _isContactsDatabaseNotConfiguredError(StateError error) {
    return error.message.contains(
      "ContactsDatabase.configure(userId: ...) must be called first",
    );
  }

  void _cacheContact(contacts.ContactRecord contact) {
    final userId = contact.contactUserId;
    final existing = _activeContactsByUserId[userId];
    final previousEmail = normalizeContactLinkEmail(existing?.email);
    if (previousEmail != null &&
        _activeContactsByNormalizedEmail[previousEmail]?.contactUserId ==
            userId) {
      _activeContactsByNormalizedEmail.remove(previousEmail);
    }
    if (contact.isDeleted) {
      _activeContactsByUserId.remove(userId);
      _invalidateProfilePictureCache(userId);
      return;
    }
    _activeContactsByUserId[userId] = contact;
    final normalizedEmail = normalizeContactLinkEmail(contact.email);
    if (normalizedEmail != null) {
      _activeContactsByNormalizedEmail[normalizedEmail] = contact;
    }
    if (existing?.profilePictureAttachmentId !=
        contact.profilePictureAttachmentId) {
      _invalidateProfilePictureCache(userId);
    }
  }

  void _resetSessionState({required bool notify}) {
    final hadCachedContacts = _activeContactsByUserId.isNotEmpty;
    _activeContactsByUserId.clear();
    _activeContactsByNormalizedEmail.clear();
    _profilePictureBytesByUserId.clear();
    _resolvedProfilePictureUserIds.clear();
    _profilePictureLoadsByUserId.clear();
    _readyFuture = null;
    _contacts = null;
    _sessionKey = null;
    _sessionAuthToken = null;
    _hasHydratedCache = false;
    if (notify && hadCachedContacts) {
      _notifyContactsChanged(null);
    }
  }

  void _invalidateProfilePictureCache(int contactUserId) {
    _profilePictureBytesByUserId.remove(contactUserId);
    _resolvedProfilePictureUserIds.remove(contactUserId);
    _profilePictureLoadsByUserId.remove(contactUserId);
  }

  void _attachSessionResetListeners() {
    Bus.instance.on<UserLoggedOutEvent>().listen((_) {
      _sessionGeneration += 1;
      _resetSessionState(notify: true);
    });
  }

  contacts.ContactsService _newContactsService() {
    final factory = _contactsServiceFactory;
    if (factory != null) {
      return factory();
    }
    throw StateError(
      "PhotosContactsService was not initialized with a contacts service factory",
    );
  }

  contacts.ContactsService _requireContacts() {
    final contacts = _contacts;
    if (contacts == null) {
      throw StateError(
        "PhotosContactsService.ensureReady() must be called before use",
      );
    }
    return contacts;
  }

  contacts.ContactsService? _activeContactsOrNull() {
    if (_sessionKey == null) {
      return null;
    }
    return _contacts;
  }

  Future<contacts.ContactsService> _ensureReadyForWrite() async {
    await ensureReady();
    final contacts = _activeContactsOrNull();
    if (contacts == null) {
      throw StateError("Contacts are unavailable without an active session");
    }
    return contacts;
  }
}
