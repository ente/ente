import 'dart:async';

import 'package:ente_contacts/src/service/contacts_service.dart';
import 'package:ente_frb/contacts.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

typedef ContactsServiceFactory = ContactsService Function();

class ContactDirectory {
  ContactDirectory({
    ContactsService? contactsService,
    ContactsServiceFactory? contactsServiceFactory,
    void Function(Set<int>? contactUserIds)? onContactsChanged,
    Logger? logger,
    Duration profilePictureFailureTtl = const Duration(minutes: 1),
  }) : _contactsServiceFactory =
           contactsServiceFactory ??
           (contactsService == null ? null : () => contactsService),
       _logger = logger ?? Logger('ContactDirectory'),
       _profilePictureFailureTtl = profilePictureFailureTtl,
       _onContactsChanged = onContactsChanged;

  final ContactsServiceFactory? _contactsServiceFactory;
  final Logger _logger;
  final Duration _profilePictureFailureTtl;
  final void Function(Set<int>? contactUserIds)? _onContactsChanged;
  final ValueNotifier<int> _revision = ValueNotifier(0);
  final Map<int, ValueNotifier<int>> _contactRevisions = {};
  final Map<int, ContactRecord> _contactsByUserId = {};
  final Map<String, ContactRecord> _contactsByEmail = {};
  final Map<int, Uint8List?> _picturesByUserId = {};
  final Map<int, Future<Uint8List?>> _pictureLoads = {};
  final Map<int, DateTime> _pictureFailureUntil = {};

  _ActiveContacts? _active;
  bool _hasHydratedCache = false;

  ValueListenable<int> get revision => _revision;

  ValueListenable<int> revisionForContact(int contactUserId) =>
      _contactRevisions.putIfAbsent(contactUserId, () => ValueNotifier(0));

  bool get hasHydratedCache => _hasHydratedCache;
  bool get needsWarmup => !_hasHydratedCache || _active?.ready == null;

  Future<void> ensureReady({
    required String baseUrl,
    required int userId,
  }) async {
    final key = '$baseUrl|$userId';
    var active = _active;
    if (active?.key != key) {
      _clear(notify: true);
      active = _ActiveContacts(key: key, service: _newContactsService());
      _active = active;
    }

    final ready = active!.ready;
    if (ready == null) {
      final opening = _hydrate(active, userId);
      active.ready = opening;
      try {
        await opening;
      } catch (error, stackTrace) {
        if (_isActive(active)) active.ready = null;
        _logger.warning('Failed to open contacts store', error, stackTrace);
        rethrow;
      }
    } else {
      await ready;
    }
  }

  Future<void> resetLocalState() async {
    final service = _active?.service;
    _clear(notify: true);
    try {
      await service?.resetLocalState();
    } finally {
      await service?.close();
    }
  }

  void clearSession({bool notify = true}) => _clear(notify: notify);

  Future<void> close({bool notify = true}) async {
    final active = _active;
    _clear(notify: notify);
    final ready = active?.ready;
    if (ready != null) {
      try {
        await ready;
      } catch (_) {}
    }
    await active?.service.close();
  }

  // Positive account IDs are authoritative and never fall back to email.
  ContactRecord? getCachedContact({int? contactUserId, String? email}) {
    if (contactUserId != null && contactUserId > 0) {
      return _contactsByUserId[contactUserId];
    }
    final normalized = _normalizeEmail(email);
    return normalized == null ? null : _contactsByEmail[normalized];
  }

  String? getCachedSavedName({int? contactUserId, String? email}) =>
      _trimToNull(
        getCachedContact(contactUserId: contactUserId, email: email)?.name,
      );

  String? getCachedResolvedEmail({int? contactUserId, String? email}) =>
      _trimToNull(
        getCachedContact(contactUserId: contactUserId, email: email)?.email,
      );

  List<ContactRecord> getCachedContacts() =>
      List.unmodifiable(_contactsByUserId.values);

  Uint8List? getCachedProfilePictureBytesByUserId(int? contactUserId) =>
      hasResolvedProfilePictureByUserId(contactUserId)
      ? _picturesByUserId[contactUserId]
      : null;

  bool hasResolvedProfilePictureByUserId(int? contactUserId) =>
      contactUserId != null && _picturesByUserId.containsKey(contactUserId);

  void preloadProfilePictureByUserId(int? contactUserId) {
    if (contactUserId == null ||
        _active == null ||
        hasResolvedProfilePictureByUserId(contactUserId) ||
        _pictureLoads.containsKey(contactUserId)) {
      return;
    }
    final contact = getCachedContact(contactUserId: contactUserId);
    if (contact == null) {
      if (_hasHydratedCache) _picturesByUserId[contactUserId] = null;
      return;
    }
    final failureUntil = _pictureFailureUntil[contactUserId];
    if (failureUntil?.isAfter(DateTime.now()) ?? false) return;

    final active = _requireActive();
    late final Future<Uint8List?> load;
    load = _loadPicture(active, contact).whenComplete(() {
      if (identical(_pictureLoads[contactUserId], load)) {
        _pictureLoads.remove(contactUserId);
      }
    });
    _pictureLoads[contactUserId] = load;
    unawaited(load);
  }

  Future<Uint8List?> getProfilePictureBytesByUserId(int? contactUserId) async {
    if (contactUserId == null || _active == null) return null;
    if (hasResolvedProfilePictureByUserId(contactUserId)) {
      return _picturesByUserId[contactUserId];
    }
    preloadProfilePictureByUserId(contactUserId);
    return _pictureLoads[contactUserId] ?? _picturesByUserId[contactUserId];
  }

  Future<ContactRecord> createOrUpdateContact({
    required int contactUserId,
    required String name,
  }) async {
    final active = _requireActive();
    final service = active.service;
    final existing = await service.getContactByUserId(
      contactUserId,
      includeDeleted: true,
    );
    _requireActiveSession(active);
    final data = ContactData(contactUserId: contactUserId, name: name.trim());
    final contact = existing == null
        ? await service.createContact(data)
        : await service.updateContact(existing.id, data);
    _requireActiveSession(active);
    _cacheAndNotify(contact);
    return contact;
  }

  Future<ContactRecord?> createContactWithProfilePictureIfAbsent({
    required int contactUserId,
    required String name,
    required Uint8List bytes,
  }) async {
    final active = _requireActive();
    final service = active.service;
    final existing = await service.getContactByUserId(
      contactUserId,
      includeDeleted: true,
    );
    if (!_isActive(active)) return null;
    if (existing != null) {
      if (!existing.isDeleted) _cache(existing);
      return existing.isDeleted ? null : existing;
    }

    final created = await service.createContact(
      ContactData(contactUserId: contactUserId, name: name.trim()),
    );
    if (!_isActive(active)) return null;
    late ContactRecord updated;
    try {
      updated = await service.setProfilePicture(created.id, bytes);
    } catch (_) {
      if (!_isActive(active)) rethrow;
      updated = await service.setProfilePicture(created.id, bytes);
    }
    if (!_isActive(active)) return null;
    _cachePicture(updated, bytes);
    return updated;
  }

  Future<ContactRecord> setProfilePicture({
    required String contactId,
    required Uint8List bytes,
  }) async {
    final active = _requireActive();
    final contact = await active.service.setProfilePicture(contactId, bytes);
    _requireActiveSession(active);
    _cachePicture(contact, bytes);
    return contact;
  }

  Future<ContactRecord> deleteProfilePicture({
    required String contactId,
  }) async {
    final active = _requireActive();
    final contact = await active.service.deleteProfilePicture(contactId);
    _requireActiveSession(active);
    _cache(contact);
    _picturesByUserId[contact.contactUserId] = null;
    _pictureFailureUntil.remove(contact.contactUserId);
    _notifyContacts({contact.contactUserId});
    return contact;
  }

  void debugHydrateContacts(
    List<ContactRecord> contacts, {
    bool markHydrated = false,
    bool notify = false,
  }) {
    final changed = _cacheAll(contacts);
    if (markHydrated) _hasHydratedCache = true;
    if (notify && changed.isNotEmpty) _notifyContacts(changed);
  }

  void debugSetProfilePictureBytes({
    required int contactUserId,
    Uint8List? bytes,
    bool notify = true,
  }) {
    _picturesByUserId[contactUserId] = bytes;
    _pictureFailureUntil.remove(contactUserId);
    _pictureLoads.remove(contactUserId);
    if (notify) _notifyContactDisplay(contactUserId);
  }

  Future<void> debugReset({bool clearLocalState = true}) async {
    final service = _active?.service;
    if (clearLocalState) await service?.resetLocalState();
    _clear(notify: false);
    _revision.value = 0;
  }

  Future<void> _hydrate(_ActiveContacts active, int userId) async {
    final service = active.service;
    await service.open(userId: userId);
    if (!_isActive(active)) return;

    final knownUserIds = _contactsByUserId.keys.toSet();
    final local = await service.getContacts();
    if (!_isActive(active)) return;
    final localChanged = _cacheAll(local);
    _hasHydratedCache = true;
    if (localChanged.isNotEmpty) {
      _notifyDisplay();
      _notifyContactDisplayAll(localChanged);
    }
    final changedUserIds = local
        .map((contact) => contact.contactUserId)
        .where((userId) => !knownUserIds.contains(userId))
        .toSet();

    try {
      final diff = await service.sync();
      if (!_isActive(active)) return;
      final diffChanged = _cacheAll(diff);
      if (diffChanged.isNotEmpty) {
        _notifyDisplay();
        _notifyContactDisplayAll(diffChanged);
      }
      changedUserIds.addAll(diff.map((contact) => contact.contactUserId));
    } catch (error, stackTrace) {
      if (!_isActive(active)) return;
      active.ready = null;
      _logger.warning(
        'Failed to sync contacts after hydrating local cache',
        error,
        stackTrace,
      );
    }
    if (changedUserIds.isNotEmpty) _notifyRecordListeners(changedUserIds);
  }

  Future<Uint8List?> _loadPicture(
    _ActiveContacts active,
    ContactRecord contact,
  ) async {
    final attachmentId = contact.profilePictureAttachmentId;
    if (attachmentId == null) {
      _picturesByUserId[contact.contactUserId] = null;
      return null;
    }
    try {
      final bytes = await active.service.getProfilePicture(contact.id);
      if (!_isActive(active)) return null;
      if (!_isCurrentPicture(contact, attachmentId)) {
        return _picturesByUserId[contact.contactUserId];
      }
      _picturesByUserId[contact.contactUserId] = bytes;
      _pictureFailureUntil.remove(contact.contactUserId);
      _notifyContactDisplay(contact.contactUserId);
      return bytes;
    } catch (error, stackTrace) {
      if (!_isActive(active)) return null;
      if (!_isCurrentPicture(contact, attachmentId)) {
        return _picturesByUserId[contact.contactUserId];
      }
      _pictureFailureUntil[contact.contactUserId] = DateTime.now().add(
        _profilePictureFailureTtl,
      );
      _logger.info(
        'Failed to load contact profile picture for user ${contact.contactUserId}',
        error,
        stackTrace,
      );
      return null;
    }
  }

  Set<int> _cacheAll(List<ContactRecord> contacts) {
    final changed = <int>{};
    for (final contact in contacts) {
      if (_cache(contact)) {
        changed.add(contact.contactUserId);
      }
    }
    return changed;
  }

  bool _cache(ContactRecord contact) {
    final previous = _contactsByUserId[contact.contactUserId];
    final previousEmail = _normalizeEmail(previous?.email);
    if (previousEmail != null &&
        _contactsByEmail[previousEmail]?.contactUserId ==
            contact.contactUserId) {
      _contactsByEmail.remove(previousEmail);
    }
    if (contact.isDeleted) {
      _contactsByUserId.remove(contact.contactUserId);
      if (previous != null) {
        _invalidatePicture(contact.contactUserId);
      }
      return previous != null;
    }

    _contactsByUserId[contact.contactUserId] = contact;
    final email = _normalizeEmail(contact.email);
    if (email != null) _contactsByEmail[email] = contact;
    if (previous?.profilePictureAttachmentId !=
        contact.profilePictureAttachmentId) {
      _invalidatePicture(contact.contactUserId);
    }
    return !_sameContact(previous, contact);
  }

  bool _sameContact(ContactRecord? a, ContactRecord b) =>
      a != null &&
      a.id == b.id &&
      a.updatedAt == b.updatedAt &&
      a.isDeleted == b.isDeleted &&
      a.email == b.email &&
      a.name == b.name &&
      a.profilePictureAttachmentId == b.profilePictureAttachmentId;

  void _cacheAndNotify(ContactRecord contact) {
    _cache(contact);
    _notifyContacts({contact.contactUserId});
  }

  void _cachePicture(ContactRecord contact, Uint8List bytes) {
    _cache(contact);
    _picturesByUserId[contact.contactUserId] = bytes;
    _pictureFailureUntil.remove(contact.contactUserId);
    _notifyContacts({contact.contactUserId});
  }

  void _clear({required bool notify}) {
    final hadContacts = _contactsByUserId.isNotEmpty;
    final contactUserIds = _contactsByUserId.keys.toList(growable: false);
    final hadDisplayState = hadContacts || _picturesByUserId.isNotEmpty;
    _active = null;
    _hasHydratedCache = false;
    _contactsByUserId.clear();
    _contactsByEmail.clear();
    _picturesByUserId.clear();
    _pictureLoads.clear();
    _pictureFailureUntil.clear();
    if (notify && hadDisplayState) _notifyDisplay();
    if (notify) _notifyContactDisplayAll(contactUserIds);
    if (notify && hadContacts) _notifyRecordListeners(null);
  }

  void _invalidatePicture(int contactUserId) {
    _picturesByUserId.remove(contactUserId);
    _pictureLoads.remove(contactUserId);
    _pictureFailureUntil.remove(contactUserId);
  }

  void _notifyContacts(Set<int> contactUserIds) {
    _notifyDisplay();
    _notifyContactDisplayAll(contactUserIds);
    _notifyRecordListeners(contactUserIds);
  }

  void _notifyDisplay() => _revision.value += 1;

  void _notifyContactDisplay(int contactUserId) {
    final revision = _contactRevisions[contactUserId];
    if (revision != null) revision.value += 1;
  }

  void _notifyContactDisplayAll(Iterable<int> contactUserIds) {
    for (final contactUserId in contactUserIds) {
      _notifyContactDisplay(contactUserId);
    }
  }

  void _notifyRecordListeners(Set<int>? contactUserIds) {
    _onContactsChanged?.call(contactUserIds);
  }

  bool _isCurrentPicture(ContactRecord contact, String attachmentId) {
    final current = _contactsByUserId[contact.contactUserId];
    return current?.id == contact.id &&
        current?.profilePictureAttachmentId == attachmentId;
  }

  _ActiveContacts _requireActive() {
    final active = _active;
    if (active == null) {
      throw StateError(
        'ContactDirectory.ensureReady(...) must be called first',
      );
    }
    return active;
  }

  void _requireActiveSession(_ActiveContacts active) {
    if (!_isActive(active)) {
      throw StateError('Contacts session changed while applying an update');
    }
  }

  bool _isActive(_ActiveContacts active) => identical(active, _active);

  ContactsService _newContactsService() {
    final factory = _contactsServiceFactory;
    if (factory == null) {
      throw StateError('ContactDirectory requires a contacts service factory');
    }
    return factory();
  }

  String? _normalizeEmail(String? value) {
    final normalized = value?.trim().toLowerCase();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  String? _trimToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class _ActiveContacts {
  _ActiveContacts({required this.key, required this.service});

  final String key;
  final ContactsService service;
  Future<void>? ready;
}
