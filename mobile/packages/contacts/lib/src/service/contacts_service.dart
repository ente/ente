import 'dart:math';
import 'dart:typed_data';

import 'package:ente_contacts/src/db/contacts_database.dart';
import 'package:ente_frb/contacts.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef CreateContact =
    Future<ContactRecordOutput> Function(
      WrappedRootContactKey? wrappedRootContactKey,
      ContactData data,
    );
typedef GetContactDiff =
    Future<ContactDiffOutput> Function(
      WrappedRootContactKey? wrappedRootContactKey,
      int sinceTime,
      int limit,
    );
typedef UpdateContact =
    Future<ContactRecordOutput> Function(
      WrappedRootContactKey? wrappedRootContactKey,
      String contactId,
      ContactData data,
    );
typedef DeleteContact = Future<void> Function(String contactId);
typedef SetContactAttachment =
    Future<ContactRecordOutput> Function(
      WrappedRootContactKey? wrappedRootContactKey,
      String contactId,
      AttachmentType attachmentType,
      Uint8List attachmentBytes,
    );
typedef DeleteContactAttachment =
    Future<ContactRecordOutput> Function(
      WrappedRootContactKey? wrappedRootContactKey,
      String contactId,
      AttachmentType attachmentType,
    );
typedef GetContactProfilePicture =
    Future<ProfilePictureOutput> Function(
      WrappedRootContactKey? wrappedRootContactKey,
      String contactId,
    );

class ContactsService {
  static const _serverMaxSyncLimit = 5000;
  static const _syncLimit = _serverMaxSyncLimit;

  ContactsService({
    required SharedPreferences preferences,
    required CreateContact createContact,
    required GetContactDiff getDiff,
    required UpdateContact updateContact,
    required DeleteContact deleteContact,
    required SetContactAttachment setAttachment,
    required DeleteContactAttachment deleteAttachment,
    required GetContactProfilePicture getProfilePicture,
    ContactsDatabase? database,
  }) : _preferences = preferences,
       _database = database ?? ContactsDatabase(),
       _createRemoteContact = createContact,
       _getRemoteDiff = getDiff,
       _updateRemoteContact = updateContact,
       _deleteRemoteContact = deleteContact,
       _setRemoteAttachment = setAttachment,
       _deleteRemoteAttachment = deleteAttachment,
       _getRemoteProfilePicture = getProfilePicture;

  final SharedPreferences _preferences;
  final ContactsDatabase _database;
  final CreateContact _createRemoteContact;
  final GetContactDiff _getRemoteDiff;
  final UpdateContact _updateRemoteContact;
  final DeleteContact _deleteRemoteContact;
  final SetContactAttachment _setRemoteAttachment;
  final DeleteContactAttachment _deleteRemoteAttachment;
  final GetContactProfilePicture _getRemoteProfilePicture;
  final Logger _logger = Logger('ContactsService');

  WrappedRootContactKey? _wrappedRootContactKey;
  int? _userId;

  Future<void> open({required int userId}) async {
    _wrappedRootContactKey = _cachedWrappedRootContactKey(userId);
    _userId = userId;
    await _database.configure(userId: userId);
    _logger.info('Opened contacts store for user $userId');
  }

  Future<List<ContactRecord>> sync() async {
    _requireOpen();
    var sinceTime = await _database.getLastSyncedUpdatedAt();
    var limit = _syncLimit;
    final synced = <ContactRecord>[];
    final syncedIds = <String>{};
    var previousSinceTime = -1;
    List<String>? previousPageIds;
    while (true) {
      final output = await _getRemoteDiff(
        _wrappedRootContactKey,
        sinceTime,
        limit,
      );
      await _saveWrappedRootContactKey(output.wrappedRootContactKey);
      final diff = output.records;
      if (diff.isEmpty) {
        break;
      }
      final pageIds = diff.map((contact) => contact.id).toList(growable: false);
      if (sinceTime == previousSinceTime &&
          previousPageIds != null &&
          _sameIds(previousPageIds, pageIds)) {
        if (limit >= _serverMaxSyncLimit) {
          throw StateError(
            'Contacts sync pagination stalled at updatedAt '
            '${diff.last.updatedAt} within server limit $_serverMaxSyncLimit',
          );
        }
        limit = min(limit * 2, _serverMaxSyncLimit);
        continue;
      }
      await _database.upsertContacts(diff);
      final maxUpdatedAt = diff.map((e) => e.updatedAt).reduce(max);
      previousSinceTime = sinceTime;
      previousPageIds = pageIds;
      sinceTime = _nextSyncCursor(diff, maxUpdatedAt, limit);
      await _database.setLastSyncedUpdatedAt(sinceTime);
      for (final contact in diff) {
        if (syncedIds.add(contact.id)) {
          synced.add(contact);
        }
      }
      if (diff.length < limit) {
        break;
      }
    }
    await _database.deleteUnreferencedCachedAttachments();
    return synced;
  }

  Future<List<ContactRecord>> getContacts({bool includeDeleted = false}) {
    return _database.getContacts(includeDeleted: includeDeleted);
  }

  Future<ContactRecord?> getContact(String contactId) {
    return _database.getContact(contactId);
  }

  Future<ContactRecord?> getContactByUserId(
    int contactUserId, {
    bool includeDeleted = false,
  }) {
    return _database.getContactByUserId(
      contactUserId,
      includeDeleted: includeDeleted,
    );
  }

  Future<ContactRecord> createContact(ContactData data) async {
    _requireOpen();
    final output = await _createRemoteContact(_wrappedRootContactKey, data);
    await _saveWrappedRootContactKey(output.wrappedRootContactKey);
    final created = output.record;
    await _database.upsertContacts([created]);
    return created;
  }

  Future<ContactRecord> updateContact(
    String contactId,
    ContactData data,
  ) async {
    _requireOpen();
    final output = await _updateRemoteContact(
      _wrappedRootContactKey,
      contactId,
      data,
    );
    await _saveWrappedRootContactKey(output.wrappedRootContactKey);
    final updated = output.record;
    await _database.upsertContacts([updated]);
    return updated;
  }

  Future<void> deleteContact(String contactId) async {
    _requireOpen();
    await _deleteRemoteContact(contactId);
    final output = await _getRemoteDiff(_wrappedRootContactKey, 0, _syncLimit);
    await _saveWrappedRootContactKey(output.wrappedRootContactKey);
    final deleted = output.records;
    final matching = deleted
        .where((element) => element.id == contactId)
        .toList();
    if (matching.isNotEmpty) {
      await _database.upsertContacts([matching.first]);
    } else {
      await sync();
    }
  }

  Future<ContactRecord> setProfilePicture(String contactId, Uint8List bytes) {
    return _setAttachment(contactId, AttachmentType.profilePicture, bytes);
  }

  Future<Uint8List> getProfilePicture(String contactId) {
    return _getProfilePicture(contactId);
  }

  Future<ContactRecord> deleteProfilePicture(String contactId) {
    return _deleteAttachment(contactId, AttachmentType.profilePicture);
  }

  Future<ContactRecord> _setAttachment(
    String contactId,
    AttachmentType attachmentType,
    Uint8List bytes,
  ) async {
    final previousAttachmentId = (await _database.getContact(
      contactId,
    ))?.profilePictureAttachmentId;
    _requireOpen();
    final output = await _setRemoteAttachment(
      _wrappedRootContactKey,
      contactId,
      attachmentType,
      bytes,
    );
    await _saveWrappedRootContactKey(output.wrappedRootContactKey);
    final updated = output.record;
    await _database.upsertContacts([updated]);
    final nextAttachmentId = updated.profilePictureAttachmentId;
    if (nextAttachmentId != null) {
      await _database.upsertCachedAttachment(nextAttachmentId, bytes);
    }
    if (previousAttachmentId != null &&
        previousAttachmentId != nextAttachmentId) {
      await _database.deleteCachedAttachment(previousAttachmentId);
    }
    return updated;
  }

  Future<Uint8List> _getProfilePicture(String contactId) async {
    final contact = await _database.getContact(contactId);
    final attachmentId = contact?.profilePictureAttachmentId;
    if (attachmentId == null) {
      throw StateError('Contact $contactId does not have a profile picture');
    }
    final cached = await _database.getCachedAttachment(attachmentId);
    if (cached != null) {
      return cached;
    }
    _requireOpen();
    final output = await _getRemoteProfilePicture(
      _wrappedRootContactKey,
      contactId,
    );
    await _saveWrappedRootContactKey(output.wrappedRootContactKey);
    final bytes = output.bytes;
    await _database.upsertCachedAttachment(attachmentId, bytes);
    return bytes;
  }

  Future<ContactRecord> _deleteAttachment(
    String contactId,
    AttachmentType attachmentType,
  ) async {
    final previousAttachmentId = (await _database.getContact(
      contactId,
    ))?.profilePictureAttachmentId;
    _requireOpen();
    final output = await _deleteRemoteAttachment(
      _wrappedRootContactKey,
      contactId,
      attachmentType,
    );
    await _saveWrappedRootContactKey(output.wrappedRootContactKey);
    final updated = output.record;
    await _database.upsertContacts([updated]);
    if (previousAttachmentId != null) {
      await _database.deleteCachedAttachment(previousAttachmentId);
    }
    return updated;
  }

  Future<void> resetLocalState() async {
    await _database.resetState();
  }

  Future<void> close() async {
    _userId = null;
    _wrappedRootContactKey = null;
    await _database.close();
  }

  int _nextSyncCursor(List<ContactRecord> diff, int maxUpdatedAt, int limit) {
    if (diff.length < limit || maxUpdatedAt <= 0) {
      return maxUpdatedAt;
    }
    // Overlap the boundary timestamp by one tick so the next page can pick up
    // additional rows that share the current page's max updatedAt.
    return maxUpdatedAt - 1;
  }

  bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  void _requireOpen() {
    if (_userId == null) {
      throw StateError('ContactsService.open(...) must be called before use');
    }
  }

  WrappedRootContactKey? _cachedWrappedRootContactKey(int userId) {
    final encryptedKey = _preferences.getString(_entityKeyPref(userId));
    final header = _preferences.getString(_entityHeaderPref(userId));
    if (encryptedKey == null || header == null) {
      return null;
    }
    return WrappedRootContactKey(encryptedKey: encryptedKey, header: header);
  }

  Future<void> _saveWrappedRootContactKey(WrappedRootContactKey? key) async {
    final userId = _userId;
    if (userId == null || key == null) return;

    _wrappedRootContactKey = key;
    await _preferences.setString(_entityKeyPref(userId), key.encryptedKey);
    await _preferences.setString(_entityHeaderPref(userId), key.header);
  }

  String _entityKeyPref(int userId) => 'entity_key_contact_$userId';

  String _entityHeaderPref(int userId) => 'entity_key_header_contact_$userId';
}
