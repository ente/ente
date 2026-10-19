import 'dart:convert';
import 'dart:io';

import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/models/file_type.dart';
import 'package:locker/models/info/info_item.dart';
import 'package:locker/services/configuration.dart';
import 'package:locker/services/files/sync/models/file.dart';
import 'package:locker/services/files/sync/models/file_magic.dart';
import 'package:locker/ui/pages/account_credentials_page.dart';
import 'package:locker/ui/pages/base_info_page.dart';
import 'package:locker/ui/pages/emergency_contact_page.dart';
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

  Finder copyTarget(TextInputComponent field) => find.descendant(
    of: find.byWidget(field),
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is GestureDetector && widget.onTap == field.onSuffixTap,
    ),
  );

  EnteFile partialFile(String type, Map<String, dynamic> data) => EnteFile()
    ..fileType = FileType.info
    ..title = (data['name'] ?? data['title']) as String
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

    await tester.enterText(find.byType(TextField).first, '');
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

    await tester.enterText(find.byType(TextField).first, '');
    expect(state.validateForm(), isFalse);
  });

  for (final password in [' secret', 'secret ', ' secret ', '   ']) {
    testWidgets('Secret saves, reopens and copies exact password "$password"', (
      tester,
    ) async {
      await showPage(tester, const AccountCredentialsPage());
      await tester.enterText(find.byType(TextField).first, '  Account  ');
      await tester.enterText(find.byType(TextField).at(1), '  username  ');
      await tester.enterText(find.byType(TextField).at(2), password);
      await tester.enterText(find.byType(TextField).at(3), '  notes  ');
      final state =
          tester.state(find.byType(AccountCredentialsPage)) as dynamic;
      final data = state.createInfoData() as AccountCredentialData;
      expect(data.password, password);
      expect(data.name, '  Account  ');
      expect(data.username, '  username  ');
      expect(data.notes, '  notes  ');
      final file = partialFile(
        'accountCredential',
        jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await showPage(tester, AccountCredentialsPage(existingFile: file));
      expect(
        tester.widget<TextField>(find.byType(TextField).at(2)).controller!.text,
        password,
      );
      final reopened =
          tester.state(find.byType(AccountCredentialsPage)) as dynamic;
      expect(reopened.hasUnsavedChanges, isFalse);
      await tester.enterText(find.byType(TextField).first, 'Renamed');
      expect(reopened.createInfoData().password, password);

      await tester.pumpWidget(const SizedBox.shrink());
      await showPage(
        tester,
        AccountCredentialsPage(mode: InfoPageMode.view, existingFile: file),
      );
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('••••••••'), findsOneWidget);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      await tester.tap(find.bySemanticsLabel('copy_password'));
      await tester.pump();
      expect(copied, password);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    });
  }

  testWidgets('Secret detects edits that only change password whitespace', (
    tester,
  ) async {
    await showPage(
      tester,
      AccountCredentialsPage(
        existingFile: partialFile('accountCredential', {
          'name': 'Account',
          'password': 'secret',
        }),
      ),
    );
    final state = tester.state(find.byType(AccountCredentialsPage)) as dynamic;
    for (final password in [' secret', 'secret ', ' secret ']) {
      await tester.enterText(find.byType(TextField).at(2), password);
      expect(state.hasUnsavedChanges, isTrue);
    }
    await tester.enterText(find.byType(TextField).at(2), 'secret');
    expect(state.hasUnsavedChanges, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await showPage(tester, const AccountCredentialsPage());
    await tester.enterText(find.byType(TextField).at(2), '   ');
    final blankState =
        tester.state(find.byType(AccountCredentialsPage)) as dynamic;
    expect(blankState.hasUnsavedChanges, isTrue);
    await tester.enterText(find.byType(TextField).at(2), '');
    expect(blankState.hasUnsavedChanges, isFalse);
  });

  testWidgets('saved whitespace-only Secret password is visible and copyable', (
    tester,
  ) async {
    await showPage(
      tester,
      AccountCredentialsPage(
        mode: InfoPageMode.view,
        existingFile: partialFile('accountCredential', {
          'name': 'Account',
          'password': '   ',
        }),
      ),
    );
    expect(find.text('Password'), findsOneWidget);
    expect(find.bySemanticsLabel('copy_password'), findsOneWidget);
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

  for (final name in ['   ', '']) {
    testWidgets(
      'shared view field uses exact emptiness for contact name "$name"',
      (tester) async {
        await showPage(
          tester,
          EmergencyContactPage(
            mode: InfoPageMode.view,
            existingFile: partialFile('emergencyContact', {
              'name': name,
              'contactDetails': '555-0100',
            }),
          ),
        );

        final fieldFinder = find.byType(TextInputComponent).first;
        final field = tester.widget<TextInputComponent>(fieldFinder);
        expect(field.initialValue, name);
        if (name.isEmpty) {
          expect(field.suffix, isNull);
          expect(field.onSuffixTap, isNull);
        } else {
          expect(field.suffix, isNotNull);
          String? copied;
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async {
              if (call.method == 'Clipboard.setData') {
                copied = (call.arguments as Map)['text'] as String;
              }
              return null;
            },
          );
          addTearDown(() {
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              SystemChannels.platform,
              null,
            );
          });
          await tester.tap(copyTarget(field));
          await tester.pump();
          expect(copied, name);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 3));
        }
      },
    );
  }

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

    await tester.enterText(find.byType(TextField).at(1), '');
    await tester.enterText(find.byType(TextField).first, 'Manual title');
    expect(state.validateForm(), isFalse);
  });

  testWidgets('generated Note titles preserve whole characters at the limit', (
    tester,
  ) async {
    await showPage(tester, const PersonalNotePage());
    final state = tester.state(find.byType(PersonalNotePage)) as dynamic;
    const prefix = 'RC285-edge-1234567890123456789012345678';

    for (final character in ['😀', '👩🏽‍💻', 'e\u0301']) {
      final content = '$prefix${character}end';
      await tester.enterText(find.byType(TextField).at(1), content);
      final data = state.createInfoData();
      expect(data.title, '$prefix$character...');
      expect(data.content, content);
    }
  });

  testWidgets('generated Note titles count emoji as whole characters', (
    tester,
  ) async {
    await showPage(tester, const PersonalNotePage());
    final state = tester.state(find.byType(PersonalNotePage)) as dynamic;
    final content = List.filled(40, '😀').join();
    await tester.enterText(find.byType(TextField).at(1), content);
    expect(state.createInfoData().title, content);
  });

  testWidgets('generated Note titles keep first-line and word limits', (
    tester,
  ) async {
    await showPage(tester, const PersonalNotePage());
    final state = tester.state(find.byType(PersonalNotePage)) as dynamic;
    for (final content in [
      '  one two three four five six\nsecond line',
      '\n\n  one two three four five six\nsecond line\n',
    ]) {
      await tester.enterText(find.byType(TextField).at(1), content);
      expect(state.createInfoData().title, 'one two three four five');
      expect(state.createInfoData().content, content);
    }

    const manualTitle = 'My 👩🏽‍💻 note title';
    await tester.enterText(find.byType(TextField).first, manualTitle);
    expect(state.createInfoData().title, manualTitle);
  });

  testWidgets('a generated emoji title reopens intact for editing', (
    tester,
  ) async {
    await showPage(tester, const PersonalNotePage());
    final state = tester.state(find.byType(PersonalNotePage)) as dynamic;
    const content = 'RC285-edge-1234567890123456789012345678😀end';
    const expectedTitle = 'RC285-edge-1234567890123456789012345678😀...';
    await tester.enterText(find.byType(TextField).at(1), content);
    final data = state.createInfoData() as PersonalNoteData;
    final file = EnteFile()
      ..fileType = FileType.info
      ..ownerID = 1
      ..title = data.title
      ..pubMagicMetadata = PubMagicMetadata(
        info: jsonDecode(jsonEncode({'type': 'note', 'data': data.toJson()})),
        noThumb: true,
      );
    await tester.pumpWidget(const SizedBox.shrink());
    await showPage(tester, PersonalNotePage(existingFile: file));

    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    expect(tester.testTextInput.editingState!['text'], expectedTitle);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      content,
    );
  });

  final infoPages = [
    (
      type: 'accountCredential',
      page: (EnteFile? file, InfoPageMode mode) =>
          AccountCredentialsPage(existingFile: file, mode: mode),
      keys: ['name', 'username', 'password', 'notes'],
      requiredIndices: [0],
      visibleKeys: ['username', 'notes'],
      titleKey: 'name',
    ),
    (
      type: 'physicalRecord',
      page: (EnteFile? file, InfoPageMode mode) =>
          PhysicalRecordsPage(existingFile: file, mode: mode),
      keys: ['name', 'location', 'notes'],
      requiredIndices: [0],
      visibleKeys: ['location', 'notes'],
      titleKey: 'name',
    ),
    (
      type: 'emergencyContact',
      page: (EnteFile? file, InfoPageMode mode) =>
          EmergencyContactPage(existingFile: file, mode: mode),
      keys: ['name', 'contactDetails', 'notes'],
      requiredIndices: [0, 1],
      visibleKeys: ['name', 'contactDetails', 'notes'],
      titleKey: '',
    ),
    (
      type: 'note',
      page: (EnteFile? file, InfoPageMode mode) =>
          PersonalNotePage(existingFile: file, mode: mode),
      keys: ['title', 'content'],
      requiredIndices: [1],
      visibleKeys: ['content'],
      titleKey: 'title',
    ),
  ];

  for (final info in infoPages) {
    testWidgets('${info.type} rejects only exactly empty required fields', (
      tester,
    ) async {
      final page = info.page(null, InfoPageMode.edit);
      await showPage(tester, page);
      final state = tester.state(find.byType(page.runtimeType)) as dynamic;
      for (final index in info.requiredIndices) {
        await tester.enterText(find.byType(TextField).at(index), ' \t\u00a0 ');
      }
      expect(state.validateForm(), isTrue);
      for (final index in info.requiredIndices) {
        await tester.enterText(find.byType(TextField).at(index), '');
        expect(state.validateForm(), isFalse);
        await tester.enterText(find.byType(TextField).at(index), ' \t\u00a0 ');
        expect(state.validateForm(), isTrue);
      }
    });

    for (final value in [
      '  entered text  ',
      ' \t\u00a0 ',
      'line one\nline two\n',
    ]) {
      testWidgets('${info.type} saves and reopens exact text "$value"', (
        tester,
      ) async {
        final page = info.page(null, InfoPageMode.edit);
        await showPage(tester, page);
        final expected = {
          for (final key in info.keys)
            key: value.contains('\n') && key != 'notes' && key != 'content'
                ? '  entered text  '
                : value,
        };
        for (var index = 0; index < info.keys.length; index++) {
          await tester.enterText(
            find.byType(TextField).at(index),
            expected[info.keys[index]]!,
          );
        }
        final state = tester.state(find.byType(page.runtimeType)) as dynamic;
        final data = state.createInfoData() as InfoData;
        expect(data.toJson(), expected);
        final file = partialFile(
          info.type,
          jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        final reopenedPage = info.page(file, InfoPageMode.edit);
        await showPage(tester, reopenedPage);
        for (var index = 0; index < info.keys.length; index++) {
          expect(
            tester
                .widget<TextField>(find.byType(TextField).at(index))
                .controller!
                .text,
            expected[info.keys[index]],
          );
        }
        final reopened = tester.state(find.byType(page.runtimeType)) as dynamic;
        expect(reopened.hasUnsavedChanges, isFalse);
        expect((reopened.createInfoData() as InfoData).toJson(), expected);
      });

      testWidgets('${info.type} displays and copies exact text "$value"', (
        tester,
      ) async {
        final data = {for (final key in info.keys) key: value};
        final page = info.page(partialFile(info.type, data), InfoPageMode.view);
        await showPage(tester, page);
        final state = tester.state(find.byType(page.runtimeType)) as dynamic;
        if (info.titleKey.isNotEmpty) {
          expect(state.pageTitle, value);
        }
        final fields = tester
            .widgetList<TextInputComponent>(find.byType(TextInputComponent))
            .where((field) => field.readOnly && field.onSuffixTap != null)
            .toList();
        expect(fields.length, info.visibleKeys.length);
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String;
            }
            return null;
          },
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
        });
        for (final field in fields) {
          expect(field.initialValue, value);
          final copyButton = copyTarget(field);
          await tester.ensureVisible(copyButton);
          await tester.pumpAndSettle();
          copied = null;
          await tester.tap(copyButton);
          await tester.pump();
          expect(copied, value);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
      });
    }

    testWidgets('${info.type} detects whitespace edits to every field', (
      tester,
    ) async {
      final page = info.page(
        partialFile(info.type, {for (final key in info.keys) key: 'value'}),
        InfoPageMode.edit,
      );
      await showPage(tester, page);
      final state = tester.state(find.byType(page.runtimeType)) as dynamic;
      expect(state.hasUnsavedChanges, isFalse);
      for (var index = 0; index < info.keys.length; index++) {
        for (final value in [' value', 'value ', '\u00a0value\t']) {
          await tester.enterText(find.byType(TextField).at(index), value);
          expect(state.hasUnsavedChanges, isTrue, reason: info.keys[index]);
          await tester.enterText(find.byType(TextField).at(index), 'value');
          expect(state.hasUnsavedChanges, isFalse);
        }
      }
    });
  }
}
