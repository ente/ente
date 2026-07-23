import 'dart:async';
import 'dart:collection';
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
  late ContactsService contactsService;
  late ContactsDisplayService displayService;
  late ContactsSession session;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    tempDir = await Directory.systemTemp.createTemp(
      'ente_contacts_display_service_test',
    );
    rustApi = FakeContactsRustApi();
    database = ContactsDatabase(directoryResolver: () async => tempDir);
    contactsService = ContactsService(
      preferences: preferences,
      database: database,
      rustApi: rustApi,
    );
    displayService = ContactsDisplayService.instance;
    await displayService.debugReset(clearLocalState: false);
    displayService.init(
      preferences: preferences,
      contactsService: contactsService,
    );
    session = ContactsSession(
      baseUrl: 'http://localhost:8080',
      authToken: 'token',
      userId: 1,
      accountKey: Uint8List.fromList([1, 2, 3]),
    );
  });

  tearDown(() async {
    await displayService.debugReset();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test(
    'ensureReady hydrates cached display data and notifies listeners',
    () async {
      rustApi.diffPages = [
        [
          const ContactRecord(
            id: 'ct_1',
            contactUserId: 7,
            email: 'alice@test.test',
            data: ContactData(contactUserId: 7, name: 'Alice'),
            profilePictureAttachmentId: 'att_1',
            isDeleted: false,
            createdAt: 1,
            updatedAt: 2,
          ),
        ],
        const [],
      ];
      var notifications = 0;
      void listener() => notifications += 1;
      displayService.changes.addListener(listener);

      await displayService.ensureReady(session);

      expect(displayService.getCachedSavedName(contactUserId: 7), 'Alice');
      expect(
        displayService.getCachedResolvedEmail(email: 'alice@test.test'),
        'alice@test.test',
      );
      expect(notifications, greaterThan(0));

      displayService.changes.removeListener(listener);
    },
  );

  test('profile picture loads are single-flight per contact', () async {
    rustApi.diffPages = [
      [
        const ContactRecord(
          id: 'ct_1',
          contactUserId: 7,
          email: 'alice@test.test',
          data: ContactData(contactUserId: 7, name: 'Alice'),
          profilePictureAttachmentId: 'att_1',
          isDeleted: false,
          createdAt: 1,
          updatedAt: 2,
        ),
      ],
      const [],
    ];
    rustApi.ctx.profilePictureBarrier = Completer<void>();
    rustApi.ctx.profilePictureBytesByContactId['ct_1'] = Uint8List.fromList([
      1,
      2,
      3,
    ]);

    await displayService.ensureReady(session);

    final first = displayService.getProfilePictureBytes(contactUserId: 7);
    final second = displayService.getProfilePictureBytes(contactUserId: 7);

    rustApi.ctx.profilePictureBarrier!.complete();
    expect(await first, Uint8List.fromList([1, 2, 3]));
    expect(await second, Uint8List.fromList([1, 2, 3]));
    expect(rustApi.ctx.getProfilePictureCalls, 1);
  });

  test('profile picture failures are briefly negative-cached', () async {
    rustApi.diffPages = [
      [
        const ContactRecord(
          id: 'ct_1',
          contactUserId: 7,
          email: 'alice@test.test',
          data: ContactData(contactUserId: 7, name: 'Alice'),
          profilePictureAttachmentId: 'att_1',
          isDeleted: false,
          createdAt: 1,
          updatedAt: 2,
        ),
      ],
      const [],
    ];
    rustApi.ctx.profilePictureError = StateError('boom');

    await displayService.ensureReady(session);

    expect(
      await displayService.getProfilePictureBytes(contactUserId: 7),
      isNull,
    );
    expect(rustApi.ctx.getProfilePictureCalls, 1);
    expect(
      await displayService.getProfilePictureBytes(contactUserId: 7),
      isNull,
    );
    expect(rustApi.ctx.getProfilePictureCalls, 1);
  });

  test(
    'stale in-flight profile picture load does not overwrite newer contact',
    () async {
      rustApi.diffPages = [
        [
          const ContactRecord(
            id: 'ct_1',
            contactUserId: 7,
            email: 'alice@test.test',
            data: ContactData(contactUserId: 7, name: 'Alice'),
            profilePictureAttachmentId: 'att_old',
            isDeleted: false,
            createdAt: 1,
            updatedAt: 2,
          ),
        ],
        const [],
      ];
      rustApi.ctx.profilePictureBarrier = Completer<void>();
      rustApi.ctx.profilePictureBytesByContactId['ct_1'] = Uint8List.fromList([
        1,
        2,
        3,
      ]);

      await displayService.ensureReady(session);

      final pending = displayService.getProfilePictureBytes(contactUserId: 7);

      displayService.debugHydrateContacts([
        const ContactRecord(
          id: 'ct_1',
          contactUserId: 7,
          email: 'alice@test.test',
          data: ContactData(contactUserId: 7, name: 'Alice'),
          profilePictureAttachmentId: 'att_new',
          isDeleted: false,
          createdAt: 1,
          updatedAt: 3,
        ),
      ], notify: false);

      rustApi.ctx.profilePictureBarrier!.complete();

      expect(await pending, isNull);
      expect(
        displayService.getCachedProfilePictureBytes(contactUserId: 7),
        isNull,
      );
    },
  );

  test(
    'stale in-flight ensureReady does not repopulate cache after session switch',
    () async {
      final diffBarrier = Completer<void>();
      rustApi.ctx.diffBarrier = diffBarrier;
      rustApi.ctx.diffStarted = Completer<void>();
      rustApi.diffPages = [
        [
          const ContactRecord(
            id: 'ct_old',
            contactUserId: 7,
            email: 'alice@test.test',
            data: ContactData(contactUserId: 7, name: 'Alice'),
            profilePictureAttachmentId: null,
            isDeleted: false,
            createdAt: 1,
            updatedAt: 2,
          ),
        ],
        const [],
      ];

      final oldEnsureReady = displayService.ensureReady(session);
      await rustApi.ctx.diffStarted!.future;

      rustApi.nextOpenContext = FakeContactsRustContext();
      rustApi.diffPages = [const []];
      final nextSession = ContactsSession(
        baseUrl: session.baseUrl,
        authToken: 'token-2',
        userId: 2,
        accountKey: Uint8List.fromList([9, 9, 9]),
      );
      await displayService.ensureReady(nextSession);

      diffBarrier.complete();
      await oldEnsureReady;

      expect(displayService.getCachedSavedName(contactUserId: 7), isNull);
      expect(
        displayService.getCachedResolvedEmail(email: 'alice@test.test'),
        isNull,
      );
    },
  );

  test('session switch creates a fresh contacts service instance', () async {
    final rustApiForFirstSession = FakeContactsRustApi();
    final rustApiForSecondSession = FakeContactsRustApi();
    final services = Queue<ContactsService>.of([
      ContactsService(
        preferences: preferences,
        database: ContactsDatabase(directoryResolver: () async => tempDir),
        rustApi: rustApiForFirstSession,
      ),
      ContactsService(
        preferences: preferences,
        database: ContactsDatabase(directoryResolver: () async => tempDir),
        rustApi: rustApiForSecondSession,
      ),
    ]);

    await displayService.debugReset(clearLocalState: false);
    displayService.init(
      preferences: preferences,
      contactsServiceFactory: () => services.removeFirst(),
    );

    rustApiForFirstSession.diffPages = [const []];
    await displayService.ensureReady(session);

    final nextSession = ContactsSession(
      baseUrl: session.baseUrl,
      authToken: 'token-2',
      userId: 2,
      accountKey: Uint8List.fromList([9, 9, 9]),
    );
    rustApiForSecondSession.diffPages = [const []];
    await displayService.ensureReady(nextSession);

    expect(rustApiForFirstSession.openCalls, 1);
    expect(rustApiForSecondSession.openCalls, 1);
    expect(services, isEmpty);
  });

  test(
    'ensureReady keeps hydrated cache and retries later when sync fails',
    () async {
      await contactsService.open(session);
      await contactsService.createContact(
        const ContactData(contactUserId: 7, name: 'Alice'),
      );
      rustApi.ctx.diffError = StateError('boom');

      await expectLater(displayService.ensureReady(session), completes);

      expect(displayService.getCachedSavedName(contactUserId: 7), 'Alice');
      expect(rustApi.ctx.getDiffCalls, 1);

      rustApi.ctx.diffError = null;
      rustApi.diffPages = [const []];

      await expectLater(displayService.ensureReady(session), completes);
      expect(rustApi.ctx.getDiffCalls, 2);
    },
  );
}

class FakeContactsRustApi implements ContactsRustApi {
  FakeContactsRustContext ctx = FakeContactsRustContext();
  FakeContactsRustContext? nextOpenContext;
  List<List<ContactRecord>> diffPages = const [];
  int openCalls = 0;

  @override
  Future<OpenContactsContextResult> open(OpenContactsContextInput input) async {
    openCalls += 1;
    final context = nextOpenContext ?? ctx;
    nextOpenContext = null;
    context.userIdValue = input.userId;
    context.diffPages = List<List<ContactRecord>>.from(diffPages);
    return OpenContactsContextResult(
      ctx: context,
      wrappedRootContactKey: const WrappedRootContactKey(
        encryptedKey: 'enc-key',
        header: 'enc-header',
      ),
      rootKeySource: RootKeySource.cache,
    );
  }
}

class FakeContactsRustContext implements ContactsRustContext {
  int userIdValue = 0;
  final Map<String, ContactRecord> records = {};
  final Map<String, Uint8List> attachments = {};
  final Map<String, Uint8List> profilePictureBytesByContactId = {};
  List<List<ContactRecord>> diffPages = [];
  int getAttachmentCalls = 0;
  int getProfilePictureCalls = 0;
  String nextAttachmentId = 'att_profile';
  Completer<void>? profilePictureBarrier;
  Completer<void>? diffBarrier;
  Completer<void>? diffStarted;
  Object? profilePictureError;
  Object? diffError;
  int getDiffCalls = 0;

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
    getDiffCalls += 1;
    final barrier = diffBarrier;
    if (barrier != null) {
      diffStarted?.complete();
      diffBarrier = null;
      await barrier.future;
    }
    final error = diffError;
    if (error != null) {
      throw error;
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
  Future<Uint8List> getProfilePicture(String contactId) async {
    getProfilePictureCalls += 1;
    final barrier = profilePictureBarrier;
    if (barrier != null) {
      await barrier.future;
    }
    final error = profilePictureError;
    if (error != null) {
      throw error;
    }
    return profilePictureBytesByContactId[contactId]!;
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
