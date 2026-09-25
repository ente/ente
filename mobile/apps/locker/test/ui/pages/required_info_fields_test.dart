import 'dart:io';

import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/file_type.dart';
import 'package:locker/services/configuration.dart';
import 'package:locker/services/files/sync/models/file.dart';
import 'package:locker/services/files/sync/models/file_magic.dart';
import 'package:locker/ui/pages/account_credentials_page.dart';
import 'package:locker/ui/pages/base_info_page.dart';
import 'package:locker/ui/pages/personal_note_page.dart';
import 'package:locker/ui/pages/physical_records_page.dart';

import '../../test_utils/configuration_test_util.dart';

void main() {
  late Directory testRoot;

  setUp(() async {
    testRoot = await setupLockerConfigurationForTest('required_info_fields');
    await Configuration.instance.setUserID(1);
  });

  tearDown(() async {
    clearLockerConfigurationTestHandlers();
    await testRoot.delete(recursive: true);
  });

  Future<void> showPage(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: page,
      ),
    );
  }

  EnteFile partialFile(String type, Map<String, dynamic> data) => EnteFile()
    ..fileType = FileType.info
    ..title = data['name'] as String
    ..pubMagicMetadata = PubMagicMetadata(
      info: {'type': type, 'data': data},
      noThumb: true,
    );

  testWidgets('Secret requires Account but accepts empty credentials', (
    tester,
  ) async {
    await showPage(tester, const AccountCredentialsPage());

    final fields = tester.widgetList<TextInputComponent>(
      find.byType(TextInputComponent),
    );
    expect(fields.where((field) => field.isRequired).length, 1);

    final state = tester.state(find.byType(AccountCredentialsPage)) as dynamic;
    await tester.enterText(find.byType(TextField).first, 'Netflix');
    expect(state.validateForm(), isTrue);
    expect(state.createInfoData().username, isEmpty);
    expect(state.createInfoData().password, isEmpty);

    await tester.enterText(find.byType(TextField).first, '  ');
    expect(state.validateForm(), isFalse);
  });

  testWidgets('Thing requires Name but accepts an empty Location', (
    tester,
  ) async {
    await showPage(tester, const PhysicalRecordsPage());

    final fields = tester.widgetList<TextInputComponent>(
      find.byType(TextInputComponent),
    );
    expect(fields.where((field) => field.isRequired).length, 1);

    final state = tester.state(find.byType(PhysicalRecordsPage)) as dynamic;
    await tester.enterText(find.byType(TextField).first, 'Passport');
    expect(state.validateForm(), isTrue);
    expect(state.createInfoData().location, isEmpty);

    await tester.enterText(find.byType(TextField).first, '  ');
    expect(state.validateForm(), isFalse);
  });

  testWidgets('partial Secret shows Notes without phantom credentials', (
    tester,
  ) async {
    await showPage(
      tester,
      AccountCredentialsPage(
        mode: InfoPageMode.view,
        existingFile: partialFile('accountCredential', {
          'name': 'Netflix',
          'notes': 'Ask Sam which email we used',
        }),
      ),
    );

    expect(find.text('Ask Sam which email we used'), findsOneWidget);
    expect(find.text('Username'), findsNothing);
    expect(find.text('Password'), findsNothing);
    expect(find.text('••••••••'), findsNothing);
  });

  testWidgets('partial Thing omits empty Location', (tester) async {
    await showPage(
      tester,
      PhysicalRecordsPage(
        mode: InfoPageMode.view,
        existingFile: partialFile('physicalRecord', {
          'name': 'Passport',
          'notes': 'Replace next year',
        }),
      ),
    );

    expect(find.text('Replace next year'), findsOneWidget);
    expect(find.text('Location'), findsNothing);
  });

  testWidgets('clearing saved credentials keeps a Secret valid', (
    tester,
  ) async {
    await showPage(
      tester,
      AccountCredentialsPage(
        existingFile: partialFile('accountCredential', {
          'name': 'Netflix',
          'username': 'old@example.com',
          'password': 'old password',
        }),
      ),
    );

    final state = tester.state(find.byType(AccountCredentialsPage)) as dynamic;
    await tester.enterText(find.byType(TextField).at(1), '');
    await tester.enterText(find.byType(TextField).at(2), '');

    expect(state.validateForm(), isTrue);
    expect(state.createInfoData().username, isEmpty);
    expect(state.createInfoData().password, isEmpty);
  });

  testWidgets('Note still requires Content and derives an empty Title', (
    tester,
  ) async {
    await showPage(tester, const PersonalNotePage());

    final state = tester.state(find.byType(PersonalNotePage)) as dynamic;
    await tester.enterText(
      find.byType(TextField).at(1),
      'Remember the spare key',
    );
    expect(state.validateForm(), isTrue);
    expect(state.createInfoData().title, 'Remember the spare key');

    await tester.enterText(find.byType(TextField).at(1), '   ');
    await tester.enterText(find.byType(TextField).first, 'Manual title');
    expect(state.validateForm(), isFalse);
  });
}
