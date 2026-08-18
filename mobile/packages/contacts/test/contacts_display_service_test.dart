import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ente_contacts/contacts.dart';
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
        [_contact(attachmentID: 'att_1')],
        const [],
      ];
      var notifications = 0;
      void listener() => notifications += 1;
      displayService.changes.addListener(listener);

      await displayService.ensureReady(session);

      expect(displayService.getCachedSavedName(contactUserId: 7), 'Alice');
      expect(notifications, greaterThan(0));

      displayService.changes.removeListener(listener);
    },
  );

  test('profile picture loads are single-flight per contact', () async {
    rustApi.diffPages = [
      [_contact(attachmentID: 'att_1')],
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
    rustApi.diffPages = [
      [_contact(attachmentID: 'att_1')],
      const [],
    ];
    rustApi.ctx.profilePictureError = StateError('boom');

    await displayService.ensureReady(session);

    expect(
      await displayService.getProfilePictureBytes(contactUserId: 7),
      isNull,
    );
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
        [_contact(attachmentID: 'att_old')],
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
        _contact(attachmentID: 'att_new', updatedAt: 3),
      ], notify: false);
      final newPicture = Uint8List.fromList([4, 5, 6]);
      displayService.debugSetProfilePictureBytes(
        contactUserId: 7,
        bytes: newPicture,
        notify: false,
      );

      rustApi.ctx.profilePictureBarrier!.complete();

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
      rustApi.ctx.diffBarrier = diffBarrier;
      rustApi.ctx.diffStarted = Completer<void>();
      rustApi.diffPages = [
        [_contact(id: 'ct_old')],
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
    },
  );

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

      await displayService.ensureReady(session);
      expect(rustApi.ctx.getDiffCalls, 2);
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
  data: ContactData(contactUserId: userID, name: name),
  profilePictureAttachmentId: attachmentID,
  isDeleted: false,
  createdAt: 1,
  updatedAt: updatedAt,
);

class FakeContactsRustApi implements ContactsRustApi {
  FakeContactsRustContext ctx = FakeContactsRustContext();
  FakeContactsRustContext? nextOpenContext;
  List<List<ContactRecord>> diffPages = const [];

  @override
  Future<OpenContactsContextResult> open(OpenContactsContextInput input) async {
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
  final Map<String, Uint8List> profilePictureBytesByContactId = {};
  List<List<ContactRecord>> diffPages = [];
  int getProfilePictureCalls = 0;
  Completer<void>? profilePictureBarrier;
  Completer<void>? diffBarrier;
  Completer<void>? diffStarted;
  Object? profilePictureError;
  Object? diffError;
  int getDiffCalls = 0;

  @override
  Future<ContactRecord> createContact(ContactData data) async {
    return ContactRecord(
      id: 'ct_created',
      contactUserId: data.contactUserId,
      email: 'b@test.test',
      data: data,
      profilePictureAttachmentId: null,
      isDeleted: false,
      createdAt: 1,
      updatedAt: 1,
    );
  }

  @override
  WrappedRootContactKey currentWrappedRootContactKey() =>
      const WrappedRootContactKey(
        encryptedKey: 'enc-key',
        header: 'enc-header',
      );

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
    return first;
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
  Future<void> updateAuthToken(String authToken) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();

  @override
  int userId() => userIdValue;
}
