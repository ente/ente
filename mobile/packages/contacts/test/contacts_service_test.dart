import 'dart:io';
import 'dart:typed_data';

import 'package:ente_contacts/contacts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late SharedPreferences preferences;
  late FakeContacts remote;
  late ContactsDatabase database;
  late ContactsService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    tempDir = await Directory.systemTemp.createTemp(
      'ente_contacts_service_test',
    );
    remote = FakeContacts();
    database = ContactsDatabase(directoryResolver: () async => tempDir);
    service = ContactsService(
      preferences: preferences,
      createContact: remote.createContact,
      getDiff: remote.getDiff,
      updateContact: remote.updateContact,
      deleteContact: remote.deleteContact,
      setAttachment: remote.setAttachment,
      deleteAttachment: remote.deleteAttachment,
      getProfilePicture: remote.getProfilePicture,
      database: database,
    );
  });

  tearDown(() async {
    await service.resetLocalState();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('sync reuses the cached root key and caches contacts', () async {
    await preferences.setString('entity_key_contact_1', 'cached-key');
    await preferences.setString('entity_key_header_contact_1', 'cached-header');

    remote.diffPages = [
      [
        const ContactRecord(
          id: 'ct_1',
          contactUserId: 2,
          email: 'b@test.test',
          name: 'B',
          profilePictureAttachmentId: 'att_1',
          isDeleted: false,
          createdAt: 10,
          updatedAt: 20,
        ),
      ],
      const [],
    ];

    await service.open(userId: 1);

    final synced = await service.sync();

    expect(remote.lastWrappedRootContactKey?.encryptedKey, 'cached-key');
    expect(remote.lastWrappedRootContactKey?.header, 'cached-header');
    expect(preferences.getString('entity_key_contact_1'), 'enc-key');
    expect(preferences.getString('entity_key_header_contact_1'), 'enc-header');
    expect(synced, hasLength(1));
    final cached = await service.getContacts();
    expect(cached.single.email, 'b@test.test');
    expect(cached.single.profilePictureAttachmentId, 'att_1');
  });

  test(
    'sync persists a resolved wrapped root contact key after unresolved open',
    () async {
      remote.diffPages = [
        [
          const ContactRecord(
            id: 'ct_1',
            contactUserId: 2,
            email: 'b@test.test',
            name: 'B',
            profilePictureAttachmentId: null,
            isDeleted: false,
            createdAt: 10,
            updatedAt: 20,
          ),
        ],
        const [],
      ];

      await service.open(userId: 1);
      expect(preferences.getString('entity_key_contact_1'), isNull);
      expect(preferences.getString('entity_key_header_contact_1'), isNull);

      await service.sync();

      expect(preferences.getString('entity_key_contact_1'), 'enc-key');
      expect(
        preferences.getString('entity_key_header_contact_1'),
        'enc-header',
      );
    },
  );

  test('create and profile-picture changes update local cache', () async {
    await service.open(userId: 1);
    expect(preferences.getString('entity_key_contact_1'), isNull);
    expect(preferences.getString('entity_key_header_contact_1'), isNull);

    final created = await service.createContact(
      const ContactData(contactUserId: 2, name: 'B'),
    );
    expect(preferences.getString('entity_key_contact_1'), 'enc-key');
    expect(preferences.getString('entity_key_header_contact_1'), 'enc-header');
    expect((await service.getContact(created.id))!.name, 'B');
    expect((await service.getContactByUserId(2))!.id, created.id);

    final updated = await service.setProfilePicture(
      created.id,
      Uint8List.fromList([1, 2, 3, 4]),
    );
    expect(updated.profilePictureAttachmentId, 'att_profile');
    expect(
      (await service.getContact(created.id))!.profilePictureAttachmentId,
      'att_profile',
    );
    expect(
      await service.getProfilePicture(created.id),
      Uint8List.fromList([1, 2, 3, 4]),
    );
    final deletedPicture = await service.deleteProfilePicture(created.id);
    expect(deletedPicture.profilePictureAttachmentId, isNull);
    expect(
      (await service.getContact(created.id))!.profilePictureAttachmentId,
      isNull,
    );
    expect(await database.getCachedAttachment('att_profile'), isNull);
  });

  test('getProfilePicture caches remote response on cache miss', () async {
    remote.diffPages = [
      [
        const ContactRecord(
          id: 'ct_1',
          contactUserId: 2,
          email: 'b@test.test',
          name: 'B',
          profilePictureAttachmentId: 'att_1',
          isDeleted: false,
          createdAt: 10,
          updatedAt: 20,
        ),
      ],
      const [],
    ];
    remote.attachments['att_1'] = Uint8List.fromList([99, 88, 77]);
    remote.profilePictures['ct_1'] = Uint8List.fromList([7, 8, 9]);

    await service.open(userId: 1);
    await service.sync();

    expect(
      await service.getProfilePicture('ct_1'),
      Uint8List.fromList([7, 8, 9]),
    );
    expect(remote.getProfilePictureCalls, 1);
    expect(
      await service.getProfilePicture('ct_1'),
      Uint8List.fromList([7, 8, 9]),
    );
    expect(remote.getProfilePictureCalls, 1);
  });

  test('replacing profile picture removes stale cached bytes', () async {
    await service.open(userId: 1);

    final created = await service.createContact(
      const ContactData(contactUserId: 2, name: 'B'),
    );
    await service.setProfilePicture(created.id, Uint8List.fromList([1, 2, 3]));
    expect(
      await service.getProfilePicture(created.id),
      Uint8List.fromList([1, 2, 3]),
    );

    remote.nextAttachmentId = 'att_profile_v2';
    final replaced = await service.setProfilePicture(
      created.id,
      Uint8List.fromList([4, 5, 6]),
    );

    expect(replaced.profilePictureAttachmentId, 'att_profile_v2');
    expect(
      await service.getProfilePicture(created.id),
      Uint8List.fromList([4, 5, 6]),
    );
    expect(await database.getCachedAttachment('att_profile'), isNull);
    expect(
      await database.getCachedAttachment('att_profile_v2'),
      Uint8List.fromList([4, 5, 6]),
    );
  });

  test(
    'sync prunes cached attachments no longer referenced by contacts',
    () async {
      remote.diffPages = [
        [
          const ContactRecord(
            id: 'ct_1',
            contactUserId: 2,
            email: 'b@test.test',
            name: 'B',
            profilePictureAttachmentId: 'att_keep',
            isDeleted: false,
            createdAt: 10,
            updatedAt: 20,
          ),
        ],
        const [],
      ];

      await service.open(userId: 1);
      await database.upsertCachedAttachment(
        'att_keep',
        Uint8List.fromList([1]),
      );
      await database.upsertCachedAttachment(
        'att_drop',
        Uint8List.fromList([2]),
      );

      await service.sync();

      expect(
        await database.getCachedAttachment('att_keep'),
        Uint8List.fromList([1]),
      );
      expect(await database.getCachedAttachment('att_drop'), isNull);
    },
  );

  test('sync clamps overlap retries to the server page cap', () async {
    final firstPage = <ContactRecord>[
      for (var i = 0; i < 5000; i++)
        ContactRecord(
          id: 'ct_$i',
          contactUserId: i + 2,
          email: 'user$i@test.test',
          name: 'User $i',
          profilePictureAttachmentId: null,
          isDeleted: false,
          createdAt: 10,
          updatedAt: 20,
        ),
    ];
    remote.diffHandler = (sinceTime, limit) async {
      if (sinceTime == 0) {
        return firstPage;
      }
      if (sinceTime == 19 && limit == 5000) {
        return firstPage;
      }
      return const [];
    };

    await service.open(userId: 1);

    await expectLater(service.sync(), throwsStateError);

    expect(remote.diffSinceTimes.first, 0);
    expect(remote.diffSinceTimes.skip(1), everyElement(19));
    expect(remote.diffLimits.first, 5000);
    expect(remote.diffLimits.every((limit) => limit <= 5000), isTrue);
  });
}

class FakeContacts {
  static const _key = WrappedRootContactKey(
    encryptedKey: 'enc-key',
    header: 'enc-header',
  );

  WrappedRootContactKey? lastWrappedRootContactKey;
  final Map<String, ContactRecord> records = {};
  final Map<String, Uint8List> attachments = {};
  final Map<String, Uint8List> profilePictures = {};
  List<List<ContactRecord>> diffPages = [];
  Future<List<ContactRecord>> Function(int sinceTime, int limit)? diffHandler;
  final List<int> diffSinceTimes = [];
  final List<int> diffLimits = [];
  int getProfilePictureCalls = 0;
  String nextAttachmentId = 'att_profile';

  Future<ContactRecordOutput> createContact(
    WrappedRootContactKey? wrappedRootContactKey,
    ContactData data,
  ) async {
    final record = ContactRecord(
      id: 'ct_created',
      contactUserId: data.contactUserId,
      email: 'b@test.test',
      name: data.name,
      profilePictureAttachmentId: null,
      isDeleted: false,
      createdAt: 1,
      updatedAt: 1,
    );
    records[record.id] = record;
    return ContactRecordOutput(record: record, wrappedRootContactKey: _key);
  }

  Future<void> deleteContact(String contactId) async {
    final existing = records[contactId];
    if (existing != null) {
      records[contactId] = ContactRecord(
        id: existing.id,
        contactUserId: existing.contactUserId,
        email: existing.email,
        name: null,
        profilePictureAttachmentId: null,
        isDeleted: true,
        createdAt: existing.createdAt,
        updatedAt: existing.updatedAt + 1,
      );
    }
  }

  Future<ContactRecordOutput> deleteAttachment(
    WrappedRootContactKey? wrappedRootContactKey,
    String contactId,
    AttachmentType attachmentType,
  ) async {
    final existing = records[contactId]!;
    final updated = ContactRecord(
      id: existing.id,
      contactUserId: existing.contactUserId,
      email: existing.email,
      name: existing.name,
      profilePictureAttachmentId: null,
      isDeleted: existing.isDeleted,
      createdAt: existing.createdAt,
      updatedAt: existing.updatedAt + 1,
    );
    records[contactId] = updated;
    final previousAttachmentId = existing.profilePictureAttachmentId;
    if (previousAttachmentId != null) {
      attachments.remove(previousAttachmentId);
    }
    return ContactRecordOutput(record: updated, wrappedRootContactKey: _key);
  }

  Future<ContactDiffOutput> getDiff(
    WrappedRootContactKey? wrappedRootContactKey,
    int sinceTime,
    int limit,
  ) async {
    lastWrappedRootContactKey = wrappedRootContactKey;
    diffSinceTimes.add(sinceTime);
    diffLimits.add(limit);
    final handler = diffHandler;
    if (handler != null) {
      final page = await handler(sinceTime, limit);
      for (final record in page) {
        records[record.id] = record;
      }
      return ContactDiffOutput(records: page, wrappedRootContactKey: _key);
    }
    if (diffPages.isEmpty) {
      return const ContactDiffOutput(records: [], wrappedRootContactKey: _key);
    }
    final first = diffPages.first;
    diffPages = diffPages.sublist(1);
    for (final record in first) {
      records[record.id] = record;
    }
    return ContactDiffOutput(records: first, wrappedRootContactKey: _key);
  }

  Future<ProfilePictureOutput> getProfilePicture(
    WrappedRootContactKey? wrappedRootContactKey,
    String contactId,
  ) async {
    getProfilePictureCalls += 1;
    final picture = profilePictures[contactId];
    if (picture != null) {
      return ProfilePictureOutput(bytes: picture, wrappedRootContactKey: _key);
    }
    final attachmentId = records[contactId]!.profilePictureAttachmentId!;
    return ProfilePictureOutput(
      bytes: attachments[attachmentId]!,
      wrappedRootContactKey: _key,
    );
  }

  Future<ContactRecordOutput> setAttachment(
    WrappedRootContactKey? wrappedRootContactKey,
    String contactId,
    AttachmentType attachmentType,
    Uint8List attachmentBytes,
  ) async {
    final existing = records[contactId]!;
    final updated = ContactRecord(
      id: existing.id,
      contactUserId: existing.contactUserId,
      email: existing.email,
      name: existing.name,
      profilePictureAttachmentId: nextAttachmentId,
      isDeleted: existing.isDeleted,
      createdAt: existing.createdAt,
      updatedAt: existing.updatedAt + 1,
    );
    records[contactId] = updated;
    attachments[nextAttachmentId] = attachmentBytes;
    profilePictures[contactId] = attachmentBytes;
    return ContactRecordOutput(record: updated, wrappedRootContactKey: _key);
  }

  Future<ContactRecordOutput> updateContact(
    WrappedRootContactKey? wrappedRootContactKey,
    String contactId,
    ContactData data,
  ) async {
    final existing = records[contactId]!;
    final updated = ContactRecord(
      id: existing.id,
      contactUserId: existing.contactUserId,
      email: existing.email,
      name: data.name,
      profilePictureAttachmentId: existing.profilePictureAttachmentId,
      isDeleted: existing.isDeleted,
      createdAt: existing.createdAt,
      updatedAt: existing.updatedAt + 1,
    );
    records[contactId] = updated;
    return ContactRecordOutput(record: updated, wrappedRootContactKey: _key);
  }
}
