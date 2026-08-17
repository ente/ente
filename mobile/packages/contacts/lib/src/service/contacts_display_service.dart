import 'package:ente_contacts/src/models/contact_record.dart';
import 'package:ente_contacts/src/models/contacts_session.dart';
import 'package:ente_contacts/src/service/contact_directory.dart';
import 'package:ente_contacts/src/service/contacts_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ContactsDisplayService {
  ContactsDisplayService._privateConstructor() : _store = ContactDirectory();

  static final ContactsDisplayService instance =
      ContactsDisplayService._privateConstructor();

  ContactDirectory _store;

  ValueListenable<int> get changes => _store.revision;

  // Known accounts keep the same notifier across cache hydration.
  ValueListenable<int> changesFor({int? contactUserId, String? email}) {
    final resolvedUserId = contactUserId != null && contactUserId > 0
        ? contactUserId
        : _resolvedContactUserId(contactUserId: contactUserId, email: email);
    return resolvedUserId == null
        ? changes
        : _store.revisionForContact(resolvedUserId);
  }

  void init({
    required SharedPreferences preferences,
    ContactsService? contactsService,
    ContactsService Function()? contactsServiceFactory,
  }) {
    _store = ContactDirectory(
      contactsService: contactsService,
      contactsServiceFactory:
          contactsServiceFactory ??
          (contactsService == null
              ? () => ContactsService(preferences: preferences)
              : null),
    );
  }

  Future<void> ensureReady(ContactsSession session) =>
      _store.ensureReady(session);

  Future<void> resetLocalState() => _store.resetLocalState();

  ContactRecord? getCachedContact({int? contactUserId, String? email}) =>
      _store.getCachedContact(contactUserId: contactUserId, email: email);

  String? getCachedSavedName({int? contactUserId, String? email}) =>
      _store.getCachedSavedName(contactUserId: contactUserId, email: email);

  String? getCachedResolvedEmail({int? contactUserId, String? email}) =>
      _store.getCachedResolvedEmail(contactUserId: contactUserId, email: email);

  Uint8List? getCachedProfilePictureBytes({int? contactUserId, String? email}) {
    final resolvedUserId = _resolvedContactUserId(
      contactUserId: contactUserId,
      email: email,
    );
    return _store.getCachedProfilePictureBytesByUserId(resolvedUserId);
  }

  bool hasResolvedProfilePicture({int? contactUserId, String? email}) {
    final resolvedUserId = _resolvedContactUserId(
      contactUserId: contactUserId,
      email: email,
    );
    return _store.hasResolvedProfilePictureByUserId(resolvedUserId);
  }

  void preloadProfilePicture({int? contactUserId, String? email}) {
    final resolvedUserId = _resolvedContactUserId(
      contactUserId: contactUserId,
      email: email,
    );
    _store.preloadProfilePictureByUserId(resolvedUserId ?? contactUserId);
  }

  Future<Uint8List?> getProfilePictureBytes({
    int? contactUserId,
    String? email,
  }) {
    final resolvedUserId = _resolvedContactUserId(
      contactUserId: contactUserId,
      email: email,
    );
    return _store.getProfilePictureBytesByUserId(
      resolvedUserId ?? contactUserId,
    );
  }

  @visibleForTesting
  Future<void> debugReset({bool clearLocalState = true}) async {
    await _store.debugReset(clearLocalState: clearLocalState);
  }

  @visibleForTesting
  void debugHydrateContacts(
    List<ContactRecord> contacts, {
    bool notify = true,
  }) {
    _store.debugHydrateContacts(contacts, markHydrated: true, notify: notify);
  }

  @visibleForTesting
  void debugSetProfilePictureBytes({
    required int contactUserId,
    Uint8List? bytes,
    bool notify = true,
  }) {
    _store.debugSetProfilePictureBytes(
      contactUserId: contactUserId,
      bytes: bytes,
      notify: notify,
    );
  }

  int? _resolvedContactUserId({int? contactUserId, String? email}) {
    return getCachedContact(
      contactUserId: contactUserId,
      email: email,
    )?.contactUserId;
  }
}
