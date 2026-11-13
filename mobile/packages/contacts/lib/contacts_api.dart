import 'package:ente_frb/contacts.dart';

abstract interface class ContactsApi {
  Future<ContactRecordOutput> createContact({
    WrappedRootContactKey? wrappedRootContactKey,
    required ContactData data,
  });

  Future<ContactDiffOutput> getDiff({
    WrappedRootContactKey? wrappedRootContactKey,
    required int sinceTime,
    required int limit,
  });

  Future<ContactRecordOutput> updateContact({
    WrappedRootContactKey? wrappedRootContactKey,
    required String contactId,
    required ContactData data,
  });

  Future<void> deleteContact({required String contactId});

  Future<ContactRecordOutput> setAttachment({
    WrappedRootContactKey? wrappedRootContactKey,
    required String contactId,
    required AttachmentType attachmentType,
    required List<int> attachmentBytes,
  });

  Future<ContactRecordOutput> deleteAttachment({
    WrappedRootContactKey? wrappedRootContactKey,
    required String contactId,
    required AttachmentType attachmentType,
  });

  Future<ProfilePictureOutput> getProfilePicture({
    WrappedRootContactKey? wrappedRootContactKey,
    required String contactId,
  });
}
