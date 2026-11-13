import 'package:ente_contacts/contacts_api.dart';
import 'package:ente_frb/contacts.dart';
import 'package:locker/src/rust/third_party/ente_frb_lib/contacts.dart'
    as contacts;
import 'package:locker/src/rust/third_party/ente_frb_lib/session.dart';

class LockerContactsApi implements ContactsApi {
  const LockerContactsApi(this._session);

  final Session _session;

  @override
  Future<ContactRecordOutput> createContact({
    WrappedRootContactKey? wrappedRootContactKey,
    required ContactData data,
  }) => contacts.createContact(
    session: _session,
    wrappedRootContactKey: wrappedRootContactKey,
    data: data,
  );

  @override
  Future<ContactDiffOutput> getDiff({
    WrappedRootContactKey? wrappedRootContactKey,
    required int sinceTime,
    required int limit,
  }) => contacts.getDiff(
    session: _session,
    wrappedRootContactKey: wrappedRootContactKey,
    sinceTime: sinceTime,
    limit: limit,
  );

  @override
  Future<ContactRecordOutput> updateContact({
    WrappedRootContactKey? wrappedRootContactKey,
    required String contactId,
    required ContactData data,
  }) => contacts.updateContact(
    session: _session,
    wrappedRootContactKey: wrappedRootContactKey,
    contactId: contactId,
    data: data,
  );

  @override
  Future<void> deleteContact({required String contactId}) =>
      contacts.deleteContact(session: _session, contactId: contactId);

  @override
  Future<ContactRecordOutput> setAttachment({
    WrappedRootContactKey? wrappedRootContactKey,
    required String contactId,
    required AttachmentType attachmentType,
    required List<int> attachmentBytes,
  }) => contacts.setAttachment(
    session: _session,
    wrappedRootContactKey: wrappedRootContactKey,
    contactId: contactId,
    attachmentType: attachmentType,
    attachmentBytes: attachmentBytes,
  );

  @override
  Future<ContactRecordOutput> deleteAttachment({
    WrappedRootContactKey? wrappedRootContactKey,
    required String contactId,
    required AttachmentType attachmentType,
  }) => contacts.deleteAttachment(
    session: _session,
    wrappedRootContactKey: wrappedRootContactKey,
    contactId: contactId,
    attachmentType: attachmentType,
  );

  @override
  Future<ProfilePictureOutput> getProfilePicture({
    WrappedRootContactKey? wrappedRootContactKey,
    required String contactId,
  }) => contacts.getProfilePicture(
    session: _session,
    wrappedRootContactKey: wrappedRootContactKey,
    contactId: contactId,
  );
}
