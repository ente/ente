import 'dart:convert';
import 'dart:typed_data';

import 'package:ente_configuration/base_configuration.dart';
import 'package:ente_contacts/contacts.dart';
import 'package:ente_sharing/models/user.dart';
import 'package:ente_sharing/resolved_user_builder.dart';
import 'package:ente_sharing/user_avator_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
        name: 'Alice',
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
        name: 'Alice',
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

Uint8List _validPngBytes() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4//8/'
  'AAX+Av6nNYGEAAAAAElFTkSuQmCC',
);
