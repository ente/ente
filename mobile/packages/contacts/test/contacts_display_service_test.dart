import 'dart:async';
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
  late ContactsService contactsService;
  late ContactsDisplayService displayService;
  const baseUrl = 'http://localhost:8080';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
    tempDir = await Directory.systemTemp.createTemp(
      'ente_contacts_display_service_test',
    );
    remote = FakeContacts();
    database = ContactsDatabase(directoryResolver: () async => tempDir);
    contactsService = remote.service(preferences, database);
    displayService = ContactsDisplayService.instance;
    await displayService.debugReset(clearLocalState: false);
    displayService.init(contactsServiceFactory: () => contactsService);
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
      remote.diffPages = [
        [_contact(attachmentID: 'att_1')],
        const [],
      ];
      var notifications = 0;
      void listener() => notifications += 1;
      displayService.changes.addListener(listener);

      await displayService.ensureReady(baseUrl: baseUrl, userId: 1);

      expect(displayService.getCachedSavedName(contactUserId: 7), 'Alice');
      expect(notifications, greaterThan(0));

      displayService.changes.removeListener(listener);
    },
  );

  test('profile picture loads are single-flight per contact', () async {
    remote.diffPages = [
      [_contact(attachmentID: 'att_1')],
      const [],
    ];
    remote.profilePictureBarrier = Completer<void>();
    remote.profilePictureBytesByContactId['ct_1'] = Uint8List.fromList([
      1,
      2,
      3,
    ]);

    await displayService.ensureReady(baseUrl: baseUrl, userId: 1);

    final first = displayService.getProfilePictureBytes(contactUserId: 7);
    final second = displayService.getProfilePictureBytes(contactUserId: 7);

    remote.profilePictureBarrier!.complete();
    expect(await first, Uint8List.fromList([1, 2, 3]));
    expect(await second, Uint8List.fromList([1, 2, 3]));
    expect(remote.getProfilePictureCalls, 1);
  });

  test('positive user id does not fall back to email', () {
    displayService.debugHydrateContacts([_contact()], notify: false);

    expect(
      displayService.getCachedContact(
        contactUserId: 99,
        email: 'alice@test.test',
      ),
      isNull,
    );
    expect(
      displayService.getCachedContact(email: 'ALICE@test.test')?.contactUserId,
      7,
    );
  });

  test('picture changes notify only the matching contact', () {
    displayService.debugHydrateContacts([
      _contact(attachmentID: 'att_1'),
      _contact(
        userID: 8,
        email: 'bob@test.test',
        name: 'Bob',
        attachmentID: 'att_2',
      ),
    ], notify: false);
    var aliceChanges = 0;
    var bobChanges = 0;
    final alice = displayService.changesFor(contactUserId: 7);
    final bob = displayService.changesFor(contactUserId: 8);
    void onAliceChanged() => aliceChanges += 1;
    void onBobChanged() => bobChanges += 1;
    alice.addListener(onAliceChanged);
    bob.addListener(onBobChanged);

    displayService.debugSetProfilePictureBytes(
      contactUserId: 7,
      bytes: Uint8List.fromList([1]),
    );

    expect(aliceChanges, 1);
    expect(bobChanges, 0);
    alice.removeListener(onAliceChanged);
    bob.removeListener(onBobChanged);
  });

  test('profile picture failures are briefly negative-cached', () async {
    remote.diffPages = [
      [_contact(attachmentID: 'att_1')],
      const [],
    ];
    remote.profilePictureError = StateError('boom');

    await displayService.ensureReady(baseUrl: baseUrl, userId: 1);

    expect(
      await displayService.getProfilePictureBytes(contactUserId: 7),
      isNull,
    );
    expect(
      await displayService.getProfilePictureBytes(contactUserId: 7),
      isNull,
    );
    expect(remote.getProfilePictureCalls, 1);
  });

  test(
    'stale in-flight profile picture load does not overwrite newer contact',
    () async {
      remote.diffPages = [
        [_contact(attachmentID: 'att_old')],
        const [],
      ];
      remote.profilePictureBarrier = Completer<void>();
      remote.profilePictureBytesByContactId['ct_1'] = Uint8List.fromList([
        1,
        2,
        3,
      ]);

      await displayService.ensureReady(baseUrl: baseUrl, userId: 1);

      final pending = displayService.getProfilePictureBytes(contactUserId: 7);

      displayService.debugHydrateContacts([
        _contact(attachmentID: 'att_new', updatedAt: 3),
      ], notify: false);
      final newPicture = Uint8List.fromList([4, 5, 6]);
      displayService.debugSetProfilePictureBytes(
        contactUserId: 7,
        bytes: newPicture,
        notify: false,
      );

      remote.profilePictureBarrier!.complete();

      expect(await pending, newPicture);
      expect(
        displayService.getCachedProfilePictureBytes(contactUserId: 7),
        newPicture,
      );
    },
  );

  test(
    'stale in-flight ensureReady does not repopulate cache after session switch',
    () async {
      final diffBarrier = Completer<void>();
      remote.diffBarrier = diffBarrier;
      remote.diffStarted = Completer<void>();
      remote.diffPages = [
        [_contact(id: 'ct_old')],
        const [],
      ];

      final oldEnsureReady = displayService.ensureReady(
        baseUrl: baseUrl,
        userId: 1,
      );
      await remote.diffStarted!.future;

      final nextDatabase = ContactsDatabase(
        directoryResolver: () async => tempDir,
      );
      contactsService = FakeContacts().service(preferences, nextDatabase);
      await displayService.ensureReady(baseUrl: baseUrl, userId: 2);

      diffBarrier.complete();
      await oldEnsureReady;

      expect(displayService.getCachedSavedName(contactUserId: 7), isNull);
      expect(await nextDatabase.getContacts(), isEmpty);
      expect((await database.getContacts()).single.id, 'ct_old');
    },
  );

  test(
    'ensureReady keeps hydrated cache and retries later when sync fails',
    () async {
      await contactsService.open(userId: 1);
      await contactsService.createContact(
        const ContactData(contactUserId: 7, name: 'Alice'),
      );
      remote.diffError = StateError('boom');

      await expectLater(
        displayService.ensureReady(baseUrl: baseUrl, userId: 1),
        completes,
      );

      expect(displayService.getCachedSavedName(contactUserId: 7), 'Alice');
      expect(remote.getDiffCalls, 1);

      remote.diffError = null;
      remote.diffPages = [const []];

      await displayService.ensureReady(baseUrl: baseUrl, userId: 1);
      expect(remote.getDiffCalls, 2);
    },
  );
}

ContactRecord _contact({
  String id = 'ct_1',
  int userID = 7,
  String email = 'alice@test.test',
  String name = 'Alice',
  String? attachmentID,
  int updatedAt = 2,
}) => ContactRecord(
  id: id,
  contactUserId: userID,
  email: email,
  name: name,
  profilePictureAttachmentId: attachmentID,
  isDeleted: false,
  createdAt: 1,
  updatedAt: updatedAt,
);

class FakeContacts {
  static const _key = WrappedRootContactKey(
    encryptedKey: 'enc-key',
    header: 'enc-header',
  );

  final Map<String, Uint8List> profilePictureBytesByContactId = {};
  List<List<ContactRecord>> diffPages = [];
  int getProfilePictureCalls = 0;
  Completer<void>? profilePictureBarrier;
  Completer<void>? diffBarrier;
  Completer<void>? diffStarted;
  Object? profilePictureError;
  Object? diffError;
  int getDiffCalls = 0;

  ContactsService service(
    SharedPreferences preferences,
    ContactsDatabase database,
  ) => ContactsService(
    preferences: preferences,
    database: database,
    createContact: createContact,
    getDiff: getDiff,
    getProfilePicture: getProfilePicture,
    updateContact: (_, _, _) => throw UnimplementedError(),
    deleteContact: (_) => throw UnimplementedError(),
    setAttachment: (_, _, _, _) => throw UnimplementedError(),
    deleteAttachment: (_, _, _) => throw UnimplementedError(),
  );

  Future<ContactRecordOutput> createContact(
    WrappedRootContactKey? wrappedRootContactKey,
    ContactData data,
  ) async {
    return ContactRecordOutput(
      record: ContactRecord(
        id: 'ct_created',
        contactUserId: data.contactUserId,
        email: 'b@test.test',
        name: data.name,
        profilePictureAttachmentId: null,
        isDeleted: false,
        createdAt: 1,
        updatedAt: 1,
      ),
      wrappedRootContactKey: _key,
    );
  }

  Future<ContactDiffOutput> getDiff(
    WrappedRootContactKey? wrappedRootContactKey,
    int sinceTime,
    int limit,
  ) async {
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
      return const ContactDiffOutput(records: [], wrappedRootContactKey: _key);
    }
    final first = diffPages.first;
    diffPages = diffPages.sublist(1);
    return ContactDiffOutput(records: first, wrappedRootContactKey: _key);
  }

  Future<ProfilePictureOutput> getProfilePicture(
    WrappedRootContactKey? wrappedRootContactKey,
    String contactId,
  ) async {
    getProfilePictureCalls += 1;
    final barrier = profilePictureBarrier;
    if (barrier != null) {
      await barrier.future;
    }
    final error = profilePictureError;
    if (error != null) {
      throw error;
    }
    return ProfilePictureOutput(
      bytes: profilePictureBytesByContactId[contactId]!,
      wrappedRootContactKey: _key,
    );
  }
}
