import 'dart:io';
import 'dart:typed_data';

import 'package:ente_contacts/contacts.dart';
import 'package:ente_contacts/src/rust/contacts_rust_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory tempDir;
  late SharedPreferences preferences;
  late FakeContactsRustApi rustApi;
  late ContactsDatabase database;
  late ContactsService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    tempDir = await Directory.systemTemp.createTemp(
      'ente_contacts_service_test',
    );
    rustApi = FakeContactsRustApi();
    database = ContactsDatabase(directoryResolver: () async => tempDir);
    service = ContactsService(
      preferences: preferences,
      rustApi: rustApi,
      database: database,
    );
  });

  tearDown(() async {
    await service.resetLocalState();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('open persists wrapped root key and sync caches contacts', () async {
    rustApi.rootKeySource = RootKeySource.cache;
    rustApi.diffPages = [
      [
        const ContactRecord(
          id: 'ct_1',
          contactUserId: 2,
          email: 'b@test.test',
          data: ContactData(contactUserId: 2, name: 'B'),
          profilePictureAttachmentId: 'att_1',
          isDeleted: false,
          createdAt: 10,
          updatedAt: 20,
        ),
      ],
      const [],
    ];

    await service.open(
      ContactsSession(
        baseUrl: 'http://localhost:8080',
        authToken: 'token',
        userId: 1,
        accountKey: Uint8List.fromList([1, 2, 3]),
      ),
    );

    expect(preferences.getString('entity_key_contact_1'), 'enc-key');
    expect(preferences.getString('entity_key_header_contact_1'), 'enc-header');

    final synced = await service.sync();
    expect(synced, hasLength(1));
    final cached = await service.getContacts();
    expect(cached.single.email, 'b@test.test');
    expect(cached.single.profilePictureAttachmentId, 'att_1');
  });

  test(
    'open does not persist an unresolved wrapped root contact key',
    () async {
      rustApi.rootKeySource = RootKeySource.unresolved;
      rustApi.openWrappedRootContactKey = null;

      await service.open(
        ContactsSession(
          baseUrl: 'http://localhost:8080',
          authToken: 'token',
          userId: 1,
          accountKey: Uint8List.fromList([1, 2, 3]),
        ),
      );

      expect(preferences.getString('entity_key_contact_1'), isNull);
      expect(preferences.getString('entity_key_header_contact_1'), isNull);
    },
  );

  test(
    'sync persists a resolved wrapped root contact key after unresolved open',
    () async {
      rustApi.rootKeySource = RootKeySource.unresolved;
      rustApi.openWrappedRootContactKey = null;
      rustApi.diffPages = [
        [
          const ContactRecord(
            id: 'ct_1',
            contactUserId: 2,
            email: 'b@test.test',
            data: ContactData(contactUserId: 2, name: 'B'),
            profilePictureAttachmentId: null,
            isDeleted: false,
            createdAt: 10,
            updatedAt: 20,
          ),
        ],
        const [],
      ];

      await service.open(
        ContactsSession(
          baseUrl: 'http://localhost:8080',
          authToken: 'token',
          userId: 1,
          accountKey: Uint8List.fromList([1, 2, 3]),
        ),
      );
      expect(preferences.getString('entity_key_contact_1'), isNull);

      await service.sync();

      expect(preferences.getString('entity_key_contact_1'), 'enc-key');
      expect(
        preferences.getString('entity_key_header_contact_1'),
        'enc-header',
      );
    },
  );

  test('create and profile-picture changes update local cache', () async {
    rustApi.rootKeySource = RootKeySource.unresolved;
    rustApi.openWrappedRootContactKey = null;
    await service.open(
      ContactsSession(
        baseUrl: 'http://localhost:8080',
        authToken: 'token',
        userId: 1,
        accountKey: Uint8List.fromList([1, 2, 3]),
      ),
    );
    expect(preferences.getString('entity_key_contact_1'), isNull);
    expect(preferences.getString('entity_key_header_contact_1'), isNull);

    final created = await service.createContact(
      const ContactData(contactUserId: 2, name: 'B'),
    );
    expect(preferences.getString('entity_key_contact_1'), 'enc-key');
    expect(preferences.getString('entity_key_header_contact_1'), 'enc-header');
    expect((await service.getContact(created.id))!.data!.name, 'B');
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
    expect(rustApi.ctx.getAttachmentCalls, 0);

    final deletedPicture = await service.deleteProfilePicture(created.id);
    expect(deletedPicture.profilePictureAttachmentId, isNull);
    expect(
      (await service.getContact(created.id))!.profilePictureAttachmentId,
      isNull,
    );
    expect(await database.getCachedAttachment('att_profile'), isNull);
  });

  test(
    'getContactByUserId resolves cached contact without scanning all rows',
    () async {
      await service.open(
        ContactsSession(
          baseUrl: 'http://localhost:8080',
          authToken: 'token',
          userId: 1,
          accountKey: Uint8List.fromList([1, 2, 3]),
        ),
      );

      final created = await service.createContact(
        const ContactData(contactUserId: 42, name: 'Douglas'),
      );

      final cached = await service.getContactByUserId(42);
      expect(cached?.id, created.id);
      expect(cached?.data?.name, 'Douglas');
    },
  );

  test('open can resolve account key from provider', () async {
    await service.open(
      ContactsSession(
        baseUrl: 'http://localhost:8080',
        authToken: 'token',
        userId: 1,
        accountKeyProvider: () async => Uint8List.fromList([9, 8, 7]),
      ),
    );

    expect(rustApi.lastAccountKey, Uint8List.fromList([9, 8, 7]));
  });

  test('getProfilePicture caches rust response on cache miss', () async {
    rustApi.diffPages = [
      [
        const ContactRecord(
          id: 'ct_1',
          contactUserId: 2,
          email: 'b@test.test',
          data: ContactData(contactUserId: 2, name: 'B'),
          profilePictureAttachmentId: 'att_1',
          isDeleted: false,
          createdAt: 10,
          updatedAt: 20,
        ),
      ],
      const [],
    ];
    rustApi.ctx.attachments['att_1'] = Uint8List.fromList([99, 88, 77]);
    rustApi.ctx.profilePictures['ct_1'] = Uint8List.fromList([7, 8, 9]);

    await service.open(
      ContactsSession(
        baseUrl: 'http://localhost:8080',
        authToken: 'token',
        userId: 1,
        accountKey: Uint8List.fromList([1, 2, 3]),
      ),
    );
    await service.sync();

    expect(
      await service.getProfilePicture('ct_1'),
      Uint8List.fromList([7, 8, 9]),
    );
    expect(rustApi.ctx.getAttachmentCalls, 0);
    expect(rustApi.ctx.getProfilePictureCalls, 1);
    expect(
      await service.getProfilePicture('ct_1'),
      Uint8List.fromList([7, 8, 9]),
    );
    expect(rustApi.ctx.getProfilePictureCalls, 1);
  });

  test('replacing profile picture removes stale cached bytes', () async {
    await service.open(
      ContactsSession(
        baseUrl: 'http://localhost:8080',
        authToken: 'token',
        userId: 1,
        accountKey: Uint8List.fromList([1, 2, 3]),
      ),
    );

    final created = await service.createContact(
      const ContactData(contactUserId: 2, name: 'B'),
    );
    await service.setProfilePicture(created.id, Uint8List.fromList([1, 2, 3]));
    expect(
      await service.getProfilePicture(created.id),
      Uint8List.fromList([1, 2, 3]),
    );

    rustApi.ctx.nextAttachmentId = 'att_profile_v2';
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
      rustApi.diffPages = [
        [
          const ContactRecord(
            id: 'ct_1',
            contactUserId: 2,
            email: 'b@test.test',
            data: ContactData(contactUserId: 2, name: 'B'),
            profilePictureAttachmentId: 'att_keep',
            isDeleted: false,
            createdAt: 10,
            updatedAt: 20,
          ),
        ],
        const [],
      ];

      await service.open(
        ContactsSession(
          baseUrl: 'http://localhost:8080',
          authToken: 'token',
          userId: 1,
          accountKey: Uint8List.fromList([1, 2, 3]),
        ),
      );
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
          data: ContactData(contactUserId: i + 2, name: 'User $i'),
          profilePictureAttachmentId: null,
          isDeleted: false,
          createdAt: 10,
          updatedAt: 20,
        ),
    ];
    rustApi.ctx.diffHandler = (sinceTime, limit) async {
      if (sinceTime == 0) {
        return firstPage;
      }
      if (sinceTime == 19 && limit == 5000) {
        return firstPage;
      }
      return const [];
    };

    await service.open(
      ContactsSession(
        baseUrl: 'http://localhost:8080',
        authToken: 'token',
        userId: 1,
        accountKey: Uint8List.fromList([1, 2, 3]),
      ),
    );

    await expectLater(service.sync(), throwsStateError);

    expect(rustApi.ctx.diffSinceTimes.first, 0);
    expect(rustApi.ctx.diffSinceTimes.skip(1), everyElement(19));
    expect(rustApi.ctx.diffLimits.first, 5000);
    expect(rustApi.ctx.diffLimits.where((limit) => limit == 5000), isNotEmpty);
    expect(rustApi.ctx.diffLimits.every((limit) => limit <= 5000), isTrue);
    expect((await service.getContact('ct_overflow'))?.data?.name, isNull);
  });
}

class FakeContactsRustApi implements ContactsRustApi {
  FakeContactsRustContext ctx = FakeContactsRustContext();
  List<List<ContactRecord>> diffPages = const [];
  Uint8List? lastAccountKey;
  RootKeySource rootKeySource = RootKeySource.cache;
  WrappedRootContactKey? openWrappedRootContactKey =
      const WrappedRootContactKey(
        encryptedKey: 'enc-key',
        header: 'enc-header',
      );

  @override
  Future<OpenContactsContextResult> open(OpenContactsContextInput input) async {
    ctx.userIdValue = input.userId;
    ctx.diffPages = List<List<ContactRecord>>.from(diffPages);
    lastAccountKey = input.accountKey;
    return OpenContactsContextResult(
      ctx: ctx,
      wrappedRootContactKey: openWrappedRootContactKey,
      rootKeySource: rootKeySource,
    );
  }
}

class FakeContactsRustContext implements ContactsRustContext {
  int userIdValue = 0;
  final Map<String, ContactRecord> records = {};
  final Map<String, Uint8List> attachments = {};
  final Map<String, Uint8List> profilePictures = {};
  List<List<ContactRecord>> diffPages = [];
  Future<List<ContactRecord>> Function(int sinceTime, int limit)? diffHandler;
  final List<int> diffSinceTimes = [];
  final List<int> diffLimits = [];
  int getAttachmentCalls = 0;
  int getProfilePictureCalls = 0;
  String nextAttachmentId = 'att_profile';

  @override
  Future<ContactRecord> createContact(ContactData data) async {
    final record = ContactRecord(
      id: 'ct_created',
      contactUserId: data.contactUserId,
      email: 'b@test.test',
      data: data,
      profilePictureAttachmentId: null,
      isDeleted: false,
      createdAt: 1,
      updatedAt: 1,
    );
    records[record.id] = record;
    return record;
  }

  @override
  WrappedRootContactKey currentWrappedRootContactKey() =>
      const WrappedRootContactKey(
        encryptedKey: 'enc-key',
        header: 'enc-header',
      );

  @override
  Future<void> deleteContact(String contactId) async {
    final existing = records[contactId];
    if (existing != null) {
      records[contactId] = ContactRecord(
        id: existing.id,
        contactUserId: existing.contactUserId,
        email: existing.email,
        data: null,
        profilePictureAttachmentId: null,
        isDeleted: true,
        createdAt: existing.createdAt,
        updatedAt: existing.updatedAt + 1,
      );
    }
  }

  @override
  Future<ContactRecord> deleteAttachment(
    String contactId,
    ContactAttachmentType attachmentType,
  ) async {
    final existing = records[contactId]!;
    final updated = ContactRecord(
      id: existing.id,
      contactUserId: existing.contactUserId,
      email: existing.email,
      data: existing.data,
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
    return updated;
  }

  @override
  Future<ContactRecord> deleteProfilePicture(String contactId) {
    return deleteAttachment(contactId, ContactAttachmentType.profilePicture);
  }

  @override
  Future<ContactRecord> getContact(String contactId) async =>
      records[contactId]!;

  @override
  Future<List<ContactRecord>> getDiff(int sinceTime, int limit) async {
    diffSinceTimes.add(sinceTime);
    diffLimits.add(limit);
    final handler = diffHandler;
    if (handler != null) {
      final page = await handler(sinceTime, limit);
      for (final record in page) {
        records[record.id] = record;
      }
      return page;
    }
    if (diffPages.isEmpty) {
      return const [];
    }
    final first = diffPages.first;
    diffPages = diffPages.sublist(1);
    for (final record in first) {
      records[record.id] = record;
    }
    return first;
  }

  @override
  Future<Uint8List> getAttachment(
    ContactAttachmentType attachmentType,
    String attachmentId,
  ) async {
    getAttachmentCalls += 1;
    return attachments[attachmentId]!;
  }

  @override
  Future<Uint8List> getProfilePicture(String contactId) {
    getProfilePictureCalls += 1;
    final picture = profilePictures[contactId];
    if (picture != null) {
      return Future.value(picture);
    }
    final attachmentId = records[contactId]!.profilePictureAttachmentId!;
    return Future.value(attachments[attachmentId]!);
  }

  @override
  Future<ContactRecord> setAttachment(
    String contactId,
    ContactAttachmentType attachmentType,
    Uint8List attachmentBytes,
  ) async {
    final existing = records[contactId]!;
    final updated = ContactRecord(
      id: existing.id,
      contactUserId: existing.contactUserId,
      email: existing.email,
      data: existing.data,
      profilePictureAttachmentId: nextAttachmentId,
      isDeleted: existing.isDeleted,
      createdAt: existing.createdAt,
      updatedAt: existing.updatedAt + 1,
    );
    records[contactId] = updated;
    attachments[nextAttachmentId] = attachmentBytes;
    profilePictures[contactId] = attachmentBytes;
    return updated;
  }

  @override
  Future<ContactRecord> setProfilePicture(
    String contactId,
    Uint8List profilePicture,
  ) {
    return setAttachment(
      contactId,
      ContactAttachmentType.profilePicture,
      profilePicture,
    );
  }

  @override
  Future<void> updateAuthToken(String authToken) async {}

  @override
  Future<ContactRecord> updateContact(
    String contactId,
    ContactData data,
  ) async {
    final existing = records[contactId]!;
    final updated = ContactRecord(
      id: existing.id,
      contactUserId: existing.contactUserId,
      email: existing.email,
      data: data,
      profilePictureAttachmentId: existing.profilePictureAttachmentId,
      isDeleted: existing.isDeleted,
      createdAt: existing.createdAt,
      updatedAt: existing.updatedAt + 1,
    );
    records[contactId] = updated;
    return updated;
  }

  @override
  int userId() => userIdValue;
}
