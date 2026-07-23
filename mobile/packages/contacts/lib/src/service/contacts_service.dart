import 'dart:math';
import 'dart:typed_data';

import 'package:ente_contacts/src/db/contacts_database.dart';
import 'package:ente_contacts/src/models/contact_data.dart';
import 'package:ente_contacts/src/models/contact_record.dart';
import 'package:ente_contacts/src/models/contacts_session.dart';
import 'package:ente_contacts/src/rust/contacts_rust_api.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ContactsService {
  static const _serverMaxSyncLimit = 5000;
  static const _syncLimit = _serverMaxSyncLimit;

  ContactsService({
    required SharedPreferences preferences,
    ContactsDatabase? database,
    ContactsRustApi? rustApi,
  }) : _preferences = preferences,
       _database = database ?? ContactsDatabase(),
       _rustApi = rustApi ?? const FrbContactsRustApi();

  final SharedPreferences _preferences;
  final ContactsDatabase _database;
  final ContactsRustApi _rustApi;
  final Logger _logger = Logger('ContactsService');

  ContactsRustContext? _ctx;
  ContactsSession? _session;

  Future<void> open(ContactsSession session) async {
    final accountKey = await session.resolveAccountKey();
    final cachedWrappedRootContactKey = _cachedWrappedRootContactKey(
      session.userId,
    );
    final opened = await _rustApi
        .open(
          OpenContactsContextInput(
            baseUrl: session.baseUrl,
            authToken: session.authToken,
            userId: session.userId,
            accountKey: accountKey,
            cachedWrappedRootContactKey: cachedWrappedRootContactKey,
            userAgent: session.userAgent,
            clientPackage: session.clientPackage,
            clientVersion: session.clientVersion,
          ),
        )
        .catchError((Object error, StackTrace stackTrace) {
          _logger.warning(
            "Failed to open contacts context for account user ${session.userId} "
            "at ${session.baseUrl} (hasCachedRootKey: ${cachedWrappedRootContactKey != null})",
            error,
            stackTrace,
          );
          throw error;
        });

    _ctx = opened.ctx;
    _session = session;
    await _database.configure(userId: session.userId);
    if (opened.wrappedRootContactKey != null) {
      await _persistWrappedRootContactKey(
        session.userId,
        opened.wrappedRootContactKey!,
      );
    }
    _logger.info('Opened contacts context for user ${session.userId}');
  }

  Future<void> updateAuthToken(String authToken) async {
    final ctx = _requireCtx();
    await ctx.updateAuthToken(authToken);
    _session = ContactsSession(
      baseUrl: _session!.baseUrl,
      authToken: authToken,
      userId: _session!.userId,
      accountKey: _session!.accountKey,
      accountKeyProvider: _session!.accountKeyProvider,
      userAgent: _session!.userAgent,
      clientPackage: _session!.clientPackage,
      clientVersion: _session!.clientVersion,
    );
  }

  Future<List<ContactRecord>> sync() async {
    final ctx = _requireCtx();
    var sinceTime = await _database.getLastSyncedUpdatedAt();
    var limit = _syncLimit;
    final synced = <ContactRecord>[];
    final syncedIds = <String>{};
    var previousSinceTime = -1;
    List<String>? previousPageIds;
    while (true) {
      final diff = await ctx.getDiff(sinceTime, limit);
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
    await _persistConfirmedWrappedRootKey();
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
    final ctx = _requireCtx();
    final created = await ctx.createContact(data);
    await _persistConfirmedWrappedRootKey();
    await _database.upsertContacts([created]);
    return created;
  }

  Future<ContactRecord> updateContact(
    String contactId,
    ContactData data,
  ) async {
    final ctx = _requireCtx();
    final updated = await ctx.updateContact(contactId, data);
    await _persistConfirmedWrappedRootKey();
    await _database.upsertContacts([updated]);
    return updated;
  }

  Future<void> deleteContact(String contactId) async {
    final ctx = _requireCtx();
    await ctx.deleteContact(contactId);
    await _persistConfirmedWrappedRootKey();
    final deleted = await ctx.getDiff(0, _syncLimit);
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
    return _setAttachment(
      contactId,
      ContactAttachmentType.profilePicture,
      bytes,
    );
  }

  Future<Uint8List> getProfilePicture(String contactId) {
    return _getProfilePicture(contactId);
  }

  Future<ContactRecord> deleteProfilePicture(String contactId) {
    return _deleteAttachment(contactId, ContactAttachmentType.profilePicture);
  }

  Future<ContactRecord> _setAttachment(
    String contactId,
    ContactAttachmentType attachmentType,
    Uint8List bytes,
  ) async {
    final previousAttachmentId = (await _database.getContact(
      contactId,
    ))?.profilePictureAttachmentId;
    final updated = await _requireCtx().setAttachment(
      contactId,
      attachmentType,
      bytes,
    );
    await _persistConfirmedWrappedRootKey();
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
    final bytes = await _requireCtx().getProfilePicture(contactId);
    await _database.upsertCachedAttachment(attachmentId, bytes);
    return bytes;
  }

  Future<ContactRecord> _deleteAttachment(
    String contactId,
    ContactAttachmentType attachmentType,
  ) async {
    final previousAttachmentId = (await _database.getContact(
      contactId,
    ))?.profilePictureAttachmentId;
    final updated = await _requireCtx().deleteAttachment(
      contactId,
      attachmentType,
    );
    await _persistConfirmedWrappedRootKey();
    await _database.upsertContacts([updated]);
    if (previousAttachmentId != null) {
      await _database.deleteCachedAttachment(previousAttachmentId);
    }
    return updated;
  }

  Future<void> resetLocalState() async {
    await _database.resetState();
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

  ContactsRustContext _requireCtx() {
    final ctx = _ctx;
    if (ctx == null) {
      throw StateError('ContactsService.open(...) must be called before use');
    }
    return ctx;
  }

  WrappedRootContactKey? _cachedWrappedRootContactKey(int userId) {
    final encryptedKey = _preferences.getString(_entityKeyPref(userId));
    final header = _preferences.getString(_entityHeaderPref(userId));
    if (encryptedKey == null || header == null) {
      return null;
    }
    return WrappedRootContactKey(encryptedKey: encryptedKey, header: header);
  }

  Future<void> _persistWrappedRootContactKey(
    int userId,
    WrappedRootContactKey key,
  ) async {
    await _preferences.setString(_entityKeyPref(userId), key.encryptedKey);
    await _preferences.setString(_entityHeaderPref(userId), key.header);
  }

  Future<void> _persistConfirmedWrappedRootKey() async {
    final session = _session;
    final ctx = _ctx;
    if (session == null || ctx == null) {
      return;
    }
    final currentWrappedRootContactKey = ctx.currentWrappedRootContactKey();
    if (currentWrappedRootContactKey == null) {
      return;
    }
    await _persistWrappedRootContactKey(
      session.userId,
      currentWrappedRootContactKey,
    );
  }

  String _entityKeyPref(int userId) => 'entity_key_contact_$userId';

  String _entityHeaderPref(int userId) => 'entity_key_header_contact_$userId';
}
