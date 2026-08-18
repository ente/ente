import 'dart:typed_data';

import 'package:ente_contacts/src/models/contact_data.dart';
import 'package:ente_contacts/src/models/contact_record.dart';

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
