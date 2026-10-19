import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/db/ml/base.dart';
import 'package:photos/ente_theme_data.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/account/user_service.dart';
import 'package:photos/services/entity_service.dart';
import 'package:photos/services/machine_learning/face_ml/person/person_service.dart';
import 'package:photos/ui/sharing/add_people_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'library_sharing_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      Configuration.userIDKey: 1,
      Configuration.emailKey: 'owner@example.com',
      UserService.keyUserDetails: jsonEncode({
        'email': 'owner@example.com',
        'usage': 0,
        'subscription': {
          'productID': 'free',
          'storage': 0,
          'originalTransactionID': '',
          'paymentProvider': '',
          'expiryTime': 0,
          'price': '',
          'period': '',
        },
        'familyData': {
          'storage': 0,
          'expiryTime': 0,
          'members': List.generate(
            8,
            (index) => {
              'id': '$index',
              'email': 'contact$index@example.com',
              'isAdmin': false,
            },
          ),
        },
      }),
    });
    final preferences = await SharedPreferences.getInstance();
    ServiceLocator.instance.init(
      preferences,
      Dio(),
      Dio(),
      Dio(),
      PackageInfo(
        appName: 'Photos',
        packageName: 'photos',
        version: '1.0.0',
        buildNumber: '1',
      ),
    );
    try {
      await Configuration.instance.init(preferences);
    } catch (_) {}
    await UserService.instance.init();
    PersonService.init(_FakeEntityService(), _FakeMLDataDB(), preferences);
  });

  testWidgets(
    'contacts start at the sheet inset and fade only after scrolling',
    (tester) async {
      await _openSheet(tester);

      final row = find.byKey(const ValueKey('contact-suggestions-scroll'));
      final first = find.byKey(
        const ValueKey('contact-suggestion-contact0@example.com'),
      );
      final leftFade = find.byWidgetPredicate(
        (widget) =>
            widget is PositionedDirectional &&
            widget.start == 0 &&
            widget.child is IgnorePointer,
      );
      expect(tester.getTopLeft(first).dx, tester.getTopLeft(row).dx);
      expect(leftFade, findsNothing);
      expect(find.byTooltip('Previous'), findsNothing);

      await tester.drag(row, const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect(leftFade, findsOneWidget);
      expect(find.byTooltip('Previous'), findsOneWidget);

      await tester.drag(row, const Offset(500, 0));
      await tester.pumpAndSettle();
      expect(leftFade, findsNothing);
      expect(tester.getTopLeft(first).dx, tester.getTopLeft(row).dx);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets('chevrons advance three contacts and clamp at the ends', (
    tester,
  ) async {
    await _openSheet(tester);
    final row = find.byKey(const ValueKey('contact-suggestions-scroll'));
    final controller = tester.widget<ListView>(row).controller!;

    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();
    expect(controller.offset, 264);
    expect(
      tester
          .getTopLeft(
            find.byKey(
              const ValueKey('contact-suggestion-contact3@example.com'),
            ),
          )
          .dx,
      tester.getTopLeft(row).dx,
    );

    await tester.tap(find.byTooltip('Previous'));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    expect(find.byTooltip('Previous'), findsNothing);

    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();
    expect(controller.offset, controller.position.maxScrollExtent);
    expect(find.byTooltip('Next'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final theme in [lightThemeData, darkThemeData]) {
    testWidgets(
      'unmatched search preserves sheet height in ${theme.brightness.name} mode',
      (tester) async {
        await _openSheet(tester, theme: theme);
        final title = find.text('Add people');
        final originalTop = tester.getTopLeft(title).dy;
        final field = find.byType(TextField);

        await tester.enterText(field, 'missing@example.com');
        await tester.pumpAndSettle();
        expect(find.text('No matching results found'), findsOneWidget);
        expect(tester.getTopLeft(title).dy, originalTop);
        expect(
          find.byKey(const ValueKey('contact-suggestions-scroll')),
          findsNothing,
        );

        await tester.enterText(field, '');
        await tester.pumpAndSettle();
        expect(find.text('No matching results found'), findsNothing);
        expect(
          find.byKey(const ValueKey('contact-suggestions-scroll')),
          findsOneWidget,
        );
        expect(tester.getTopLeft(title).dy, originalTop);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

Future<void> _openSheet(WidgetTester tester, {ThemeData? theme}) async {
  await tester.binding.setSurfaceSize(const Size(402, 874));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? darkThemeData,
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      supportedLocales: StringsLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () =>
                  showAddPeopleSheet(context, [librarySharingTestAlbum(1)]),
              child: const Text('Open'),
            );
          },
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

class _FakeEntityService extends Fake implements EntityService {}

class _FakeMLDataDB extends Fake implements IMLDataDB<int> {}
