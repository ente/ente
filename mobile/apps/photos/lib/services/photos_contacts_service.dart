import "package:ente_contacts/contacts.dart" as contacts;
import "package:flutter/foundation.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/contacts_changed_event.dart";
import "package:photos/events/user_logged_out_event.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/frb_contacts_rust_api.dart";

// Photos-specific session and event adapter for the shared contact directory.
class PhotosContactsService {
  PhotosContactsService._privateConstructor()
    : _store = contacts.ContactDirectory(
        contactsServiceFactory: () => contacts.ContactsService(
          preferences: ServiceLocator.instance.prefs,
          rustApi: const FrbContactsRustApi(),
        ),
        onContactsChanged: _notifyContactsChanged,
        profilePictureFailureTtl: Duration.zero,
      ) {
    _attachSessionResetListener();
  }

  @visibleForTesting
  PhotosContactsService.forTesting({
    contacts.ContactsService? contactsService,
    contacts.ContactsService Function()? contactsServiceFactory,
  }) : _store = contacts.ContactDirectory(
         contactsService: contactsService,
         contactsServiceFactory: contactsServiceFactory,
         onContactsChanged: _notifyContactsChanged,
         profilePictureFailureTtl: Duration.zero,
       ) {
    _attachSessionResetListener();
  }

  static final PhotosContactsService instance =
      PhotosContactsService._privateConstructor();

  final contacts.ContactDirectory _store;
  final _logger = Logger("PhotosContactsService");

  bool get hasHydratedCache => _store.hasHydratedCache;

  bool get needsWarmup => _store.needsWarmup;

  Future<void> ensureReady() async {
    final session = _buildSession();
    if (session == null) {
      _store.clearSession();
      return;
    }
    await _store.ensureReady(session);
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
      return getCachedContact(contactUserId: contactUserId, email: email);
    }, description: "load contact for user $contactUserId");
  }

  contacts.ContactRecord? getCachedContact({
    int? contactUserId,
    String? email,
  }) => _store.getCachedContact(contactUserId: contactUserId, email: email);

  List<contacts.ContactRecord> getCachedContacts() =>
      _store.getCachedContacts();

  String? getCachedSavedName({int? contactUserId, String? email}) =>
      _store.getCachedSavedName(contactUserId: contactUserId, email: email);

  String? getCachedResolvedEmail({int? contactUserId, String? email}) =>
      _store.getCachedResolvedEmail(contactUserId: contactUserId, email: email);

  Uint8List? getCachedProfilePictureBytesByUserId(int? contactUserId) =>
      _store.getCachedProfilePictureBytesByUserId(contactUserId);

  bool hasResolvedProfilePictureByUserId(int? contactUserId) =>
      _store.hasResolvedProfilePictureByUserId(contactUserId);

  Future<Uint8List?> getProfilePictureBytesByUserId(int? contactUserId) async {
    if (contactUserId == null) {
      return null;
    }
    if (_store.hasResolvedProfilePictureByUserId(contactUserId)) {
      return _store.getCachedProfilePictureBytesByUserId(contactUserId);
    }
    await getContact(contactUserId: contactUserId);
    return _store.getProfilePictureBytesByUserId(contactUserId);
  }

  Future<contacts.ContactRecord> createOrUpdateContact({
    required int contactUserId,
    required String name,
  }) async {
    await ensureReady();
    return _store.createOrUpdateContact(
      contactUserId: contactUserId,
      name: name,
    );
  }

  Future<contacts.ContactRecord?> createContactWithProfilePictureIfAbsent({
    required int contactUserId,
    required String name,
    required Uint8List bytes,
  }) async {
    await ensureReady();
    return _store.createContactWithProfilePictureIfAbsent(
      contactUserId: contactUserId,
      name: name,
      bytes: bytes,
    );
  }

  Future<contacts.ContactRecord> setProfilePicture({
    required String contactId,
    required Uint8List bytes,
  }) async {
    await ensureReady();
    return _store.setProfilePicture(contactId: contactId, bytes: bytes);
  }

  Future<contacts.ContactRecord> deleteProfilePicture({
    required String contactId,
  }) async {
    await ensureReady();
    return _store.deleteProfilePicture(contactId: contactId);
  }

  @visibleForTesting
  Future<void> debugOpenAndSync(contacts.ContactsSession session) =>
      _store.ensureReady(session);

  @visibleForTesting
  void debugHydrateContacts(
    List<contacts.ContactRecord> records, {
    bool markHydrated = false,
  }) => _store.debugHydrateContacts(records, markHydrated: markHydrated);

  @visibleForTesting
  void debugReset({bool notify = false}) => _store.clearSession(notify: notify);

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

  Future<T?> _runReadSafely<T>(
    Future<T?> Function() task, {
    required String description,
  }) async {
    try {
      return await task();
    } on StateError catch (error, stackTrace) {
      if (_isRustInitializationError(error)) {
        _logger.warning(
          "Contacts integration unavailable while Rust bindings are not initialized during $description. Photos initializes EntePhotosRust in main.dart.",
          error,
          stackTrace,
        );
        return null;
      }
      if (_isContactsDatabaseNotConfiguredError(error)) {
        _logger.warning(
          "Contacts integration unavailable while contacts are disabled or not initialized during $description",
          error,
          stackTrace,
        );
        return null;
      }
      rethrow;
    } catch (error, stackTrace) {
      _logger.warning("Failed to $description", error, stackTrace);
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

  static void _notifyContactsChanged(Set<int>? contactUserIds) {
    Bus.instance.fire(ContactsChangedEvent(contactUserIds: contactUserIds));
  }

  void _attachSessionResetListener() {
    Bus.instance.on<UserLoggedOutEvent>().listen((_) {
      _store.clearSession();
    });
  }
}
