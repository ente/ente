import 'dart:typed_data';

import 'package:ente_contacts/src/models/contact_data.dart';
import 'package:ente_contacts/src/models/contact_record.dart';
import 'package:ente_rust/ente_rust.dart' as rust;

class WrappedRootContactKey {
  final String encryptedKey;
  final String header;

  const WrappedRootContactKey({
    required this.encryptedKey,
    required this.header,
  });
}

enum ContactAttachmentType { profilePicture }

enum RootKeySource { cache, unresolved }

class OpenContactsContextInput {
  final String baseUrl;
  final String authToken;
  final int userId;
  final Uint8List accountKey;
  final WrappedRootContactKey? cachedWrappedRootContactKey;
  final String? userAgent;
  final String? clientPackage;
  final String? clientVersion;

  const OpenContactsContextInput({
    required this.baseUrl,
    required this.authToken,
    required this.userId,
    required this.accountKey,
    this.cachedWrappedRootContactKey,
    this.userAgent,
    this.clientPackage,
    this.clientVersion,
  });
}

class OpenContactsContextResult {
  final ContactsRustContext ctx;
  final WrappedRootContactKey? wrappedRootContactKey;
  final RootKeySource rootKeySource;

  const OpenContactsContextResult({
    required this.ctx,
    required this.wrappedRootContactKey,
    required this.rootKeySource,
  });
}

abstract class ContactsRustContext {
  int userId();

  Future<void> updateAuthToken(String authToken);

  WrappedRootContactKey? currentWrappedRootContactKey();

  Future<ContactRecord> createContact(ContactData data);

  Future<ContactRecord> getContact(String contactId);

  Future<List<ContactRecord>> getDiff(int sinceTime, int limit);

  Future<ContactRecord> updateContact(String contactId, ContactData data);

  Future<void> deleteContact(String contactId);

  Future<ContactRecord> setAttachment(
    String contactId,
    ContactAttachmentType attachmentType,
    Uint8List attachmentBytes,
  );

  Future<Uint8List> getAttachment(
    ContactAttachmentType attachmentType,
    String attachmentId,
  );

  Future<ContactRecord> deleteAttachment(
    String contactId,
    ContactAttachmentType attachmentType,
  );

  Future<ContactRecord> setProfilePicture(
    String contactId,
    Uint8List profilePicture,
  );

  Future<Uint8List> getProfilePicture(String contactId);

  Future<ContactRecord> deleteProfilePicture(String contactId);
}

abstract class ContactsRustApi {
  Future<OpenContactsContextResult> open(OpenContactsContextInput input);
}

class FrbContactsRustApi implements ContactsRustApi {
  const FrbContactsRustApi();

  @override
  Future<OpenContactsContextResult> open(OpenContactsContextInput input) async {
    final result = await rust.openContactsCtx(
      input: rust.OpenContactsCtxInput(
        baseUrl: input.baseUrl,
        authToken: input.authToken,
        userId: input.userId,
        masterKey: input.accountKey,
        cachedWrappedRootContactKey: input.cachedWrappedRootContactKey == null
            ? null
            : rust.WrappedRootContactKey(
                encryptedKey: input.cachedWrappedRootContactKey!.encryptedKey,
                header: input.cachedWrappedRootContactKey!.header,
              ),
        userAgent: input.userAgent,
        clientPackage: input.clientPackage,
        clientVersion: input.clientVersion,
      ),
    );

    return OpenContactsContextResult(
      ctx: _FrbContactsRustContext(result.ctx),
      wrappedRootContactKey: result.wrappedRootContactKey == null
          ? null
          : WrappedRootContactKey(
              encryptedKey: result.wrappedRootContactKey!.encryptedKey,
              header: result.wrappedRootContactKey!.header,
            ),
      rootKeySource: switch (result.rootKeySource) {
        rust.RootKeySource.cache => RootKeySource.cache,
        rust.RootKeySource.unresolved => RootKeySource.unresolved,
      },
    );
  }
}

class _FrbContactsRustContext implements ContactsRustContext {
  final rust.ContactsCtx _inner;

  const _FrbContactsRustContext(this._inner);

  @override
  int userId() => _inner.userId();

  @override
  Future<void> updateAuthToken(String authToken) {
    return _inner.updateAuthToken(authToken: authToken);
  }

  @override
  WrappedRootContactKey? currentWrappedRootContactKey() {
    final current = _inner.currentWrappedRootContactKey();
    if (current == null) {
      return null;
    }
    return WrappedRootContactKey(
      encryptedKey: current.encryptedKey,
      header: current.header,
    );
  }

  @override
  Future<ContactRecord> createContact(ContactData data) async {
    return _fromRustRecord(
      await _inner.createContact(
        data: rust.ContactData(
          contactUserId: data.contactUserId,
          name: data.name,
        ),
      ),
    );
  }

  @override
  Future<ContactRecord> getContact(String contactId) async {
    return _fromRustRecord(await _inner.getContact(contactId: contactId));
  }

  @override
  Future<List<ContactRecord>> getDiff(int sinceTime, int limit) async {
    final diff = await _inner.getDiff(sinceTime: sinceTime, limit: limit);
    return diff.map(_fromRustRecord).toList(growable: false);
  }

  @override
  Future<ContactRecord> updateContact(
    String contactId,
    ContactData data,
  ) async {
    return _fromRustRecord(
      await _inner.updateContact(
        contactId: contactId,
        data: rust.ContactData(
          contactUserId: data.contactUserId,
          name: data.name,
        ),
      ),
    );
  }

  @override
  Future<void> deleteContact(String contactId) {
    return _inner.deleteContact(contactId: contactId);
  }

  @override
  Future<ContactRecord> setAttachment(
    String contactId,
    ContactAttachmentType attachmentType,
    Uint8List attachmentBytes,
  ) async {
    return _fromRustRecord(
      await _inner.setAttachment(
        contactId: contactId,
        attachmentType: _toRustAttachmentType(attachmentType),
        attachmentBytes: attachmentBytes,
      ),
    );
  }

  @override
  Future<Uint8List> getAttachment(
    ContactAttachmentType attachmentType,
    String attachmentId,
  ) {
    return _inner.getAttachmentEncrypted(
      attachmentType: _toRustAttachmentType(attachmentType),
      attachmentId: attachmentId,
    );
  }

  @override
  Future<ContactRecord> deleteAttachment(
    String contactId,
    ContactAttachmentType attachmentType,
  ) async {
    return _fromRustRecord(
      await _inner.deleteAttachment(
        contactId: contactId,
        attachmentType: _toRustAttachmentType(attachmentType),
      ),
    );
  }

  @override
  Future<ContactRecord> setProfilePicture(
    String contactId,
    Uint8List profilePicture,
  ) async {
    return setAttachment(
      contactId,
      ContactAttachmentType.profilePicture,
      profilePicture,
    );
  }

  @override
  Future<Uint8List> getProfilePicture(String contactId) {
    return _inner.getProfilePicture(contactId: contactId);
  }

  @override
  Future<ContactRecord> deleteProfilePicture(String contactId) async {
    return deleteAttachment(contactId, ContactAttachmentType.profilePicture);
  }
}

rust.AttachmentType _toRustAttachmentType(
  ContactAttachmentType attachmentType,
) {
  return switch (attachmentType) {
    ContactAttachmentType.profilePicture => rust.AttachmentType.profilePicture,
  };
}

ContactRecord _fromRustRecord(rust.ContactRecord record) {
  final data = record.isDeleted
      ? null
      : ContactData(contactUserId: record.contactUserId, name: record.name!);
  return ContactRecord(
    id: record.id,
    contactUserId: record.contactUserId,
    email: record.email,
    data: data,
    profilePictureAttachmentId: record.profilePictureAttachmentId,
    isDeleted: record.isDeleted,
    createdAt: record.createdAt,
    updatedAt: record.updatedAt,
  );
}
