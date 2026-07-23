import 'dart:typed_data';

import 'package:ente_configuration/base_configuration.dart';
import 'package:ente_contacts/contacts.dart';
import 'package:ente_sharing/models/user.dart';
import 'package:ente_sharing/resolved_user_builder.dart';
import 'package:ente_sharing/user_avator_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ContactsDisplayService displayService;

  setUp(() async {
    displayService = ContactsDisplayService.instance;
    await displayService.debugReset(clearLocalState: false);
  });

  tearDown(() async {
    await displayService.debugReset();
  });

  testWidgets('user avatar prefers saved contact photo over initials', (
    tester,
  ) async {
    displayService.debugHydrateContacts(const [
      ContactRecord(
        id: 'ct_1',
        contactUserId: 7,
        email: 'z@test.test',
        data: ContactData(contactUserId: 7, name: 'Alice'),
        profilePictureAttachmentId: 'att_1',
        isDeleted: false,
        createdAt: 1,
        updatedAt: 2,
      ),
    ], notify: false);
    displayService.debugSetProfilePictureBytes(
      contactUserId: 7,
      bytes: _validPngBytes(),
      notify: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UserAvatarWidget(
            User(id: 7, email: 'z@test.test'),
            config: _TestConfiguration(),
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('A'), findsNothing);
  });

  testWidgets('resolved user builder refreshes when contacts hydrate', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ResolvedUserBuilder(
            user: User(id: 7, email: 'z@test.test'),
            builder: (context, displayName, _) => Text(displayName),
          ),
        ),
      ),
    );

    expect(find.text('z@test.test'), findsOneWidget);

    displayService.debugHydrateContacts(const [
      ContactRecord(
        id: 'ct_1',
        contactUserId: 7,
        email: 'z@test.test',
        data: ContactData(contactUserId: 7, name: 'Alice'),
        profilePictureAttachmentId: null,
        isDeleted: false,
        createdAt: 1,
        updatedAt: 2,
      ),
    ]);
    await tester.pump();

    expect(find.text('Alice'), findsOneWidget);
  });
}

class _TestConfiguration extends BaseConfiguration {
  @override
  EnteAppIdentity get appIdentity => const EnteAppIdentity(
    app: 'test',
    clientPackageName: 'io.ente.test',
    passkeyRedirectUrl: 'entetest://passkey',
    referralSourcePrefix: 'test',
  );

  @override
  List<String> get secureStorageKeys =>
      BaseConfiguration.accountSecureStorageKeys;

  @override
  String? getEmail() => 'me@test.test';

  @override
  int? getUserID() => 1;
}

Uint8List _validPngBytes() {
  return Uint8List.fromList(const [
    137,
    80,
    78,
    71,
    13,
    10,
    26,
    10,
    0,
    0,
    0,
    13,
    73,
    72,
    68,
    82,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    1,
    8,
    6,
    0,
    0,
    0,
    31,
    21,
    196,
    137,
    0,
    0,
    0,
    13,
    73,
    68,
    65,
    84,
    120,
    156,
    99,
    248,
    255,
    255,
    63,
    0,
    5,
    254,
    2,
    254,
    167,
    53,
    129,
    132,
    0,
    0,
    0,
    0,
    73,
    69,
    78,
    68,
    174,
    66,
    96,
    130,
  ]);
}
