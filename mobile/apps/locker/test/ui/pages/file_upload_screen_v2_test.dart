import 'dart:io';

import 'package:ente_components/ente_components.dart';
import 'package:ente_sharing/models/user.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/services/configuration.dart';
import 'package:locker/ui/components/collection_selection_widget.dart';
import 'package:locker/ui/pages/file_upload_screen.dart';
import 'package:locker/ui/pages/file_upload_screen_v2.dart';

import '../../test_utils/configuration_test_util.dart';

void main() {
  late Directory testRoot;

  setUp(() async {
    testRoot = await setupLockerConfigurationForTest('upload_v2');
    await Configuration.instance.setUserID(1);
  });

  tearDown(() async {
    clearLockerConfigurationTestHandlers();
    await testRoot.delete(recursive: true);
  });

  Collection collection(int id, String name) => Collection(
    id,
    User(id: 1, email: 'a@b.c'),
    '',
    null,
    name,
    null,
    null,
    CollectionType.folder,
    CollectionAttributes(),
    const [],
    const [],
    0,
  );
  final files = [
    File('/upload/Passport_scan.pdf'),
    File('/upload/IMG_4821.png'),
  ];

  Future<void> showScreen(
    WidgetTester tester, {
    List<Collection> collections = const [],
    List<File>? uploadFiles,
    Collection? selectedCollection,
    void Function(FileUploadScreenResult?)? onSaved,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              final result = await Navigator.of(context)
                  .push<FileUploadScreenResult>(
                    MaterialPageRoute(
                      builder: (_) => FileUploadScreenV2(
                        files: uploadFiles ?? files,
                        collections: collections,
                        selectedCollection: selectedCollection,
                      ),
                    ),
                  );
              onSaved?.call(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> openRowMenu(WidgetTester tester) async {
    await tester.tap(
      find
          .byWidgetPredicate(
            (w) =>
                w is HugeIcon && w.icon == HugeIcons.strokeRoundedMoreVertical,
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('collection chips toggle and save the selected destinations', (
    tester,
  ) async {
    final passport = collection(10, 'Passport');
    final travel = collection(20, 'Travel');
    FileUploadScreenResult? saved;
    await showScreen(
      tester,
      collections: [passport, travel],
      selectedCollection: passport,
      onSaved: (result) => saved = result,
    );

    final passportChip = find.widgetWithText(TagChipComponent, 'Passport');
    final travelChip = find.widgetWithText(TagChipComponent, 'Travel');
    expect(
      tester.widget<TagChipComponent>(passportChip).state,
      TagChipComponentState.selected,
    );
    await tester.tap(travelChip);
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(passportChip);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ButtonComponent, 'Save'));
    await tester.pumpAndSettle();

    expect(saved!.selectedCollections.map((c) => c.id), [20]);
    expect(saved!.files.map((file) => file.path), [
      '/upload/Passport_scan.pdf',
      '/upload/IMG_4821.png',
    ]);
  });

  testWidgets(
    'saving with no selected collection uses the uncategorized path',
    (tester) async {
      FileUploadScreenResult? saved;
      await showScreen(tester, onSaved: (result) => saved = result);
      await tester.tap(find.widgetWithText(ButtonComponent, 'Save'));
      await tester.pumpAndSettle();
      expect(saved!.selectedCollections, isEmpty);
    },
  );

  testWidgets('removing every file shows the empty state instead of popping', (
    tester,
  ) async {
    await showScreen(tester);

    for (var i = 0; i < files.length; i++) {
      await openRowMenu(tester);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
    }

    expect(find.byType(FileUploadScreenV2), findsOneWidget);
    expect(find.text('No items left to upload'), findsOneWidget);
    expect(find.text('Add items'), findsOneWidget);
    final save = tester.widget<ButtonComponent>(
      find.widgetWithText(ButtonComponent, 'Save'),
    );
    expect(save.isDisabled, isTrue);
  });

  testWidgets('rename from the row menu keeps the extension', (tester) async {
    await showScreen(tester);

    await openRowMenu(tester);
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Passport 2026');
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheetComponent),
        matching: find.text('Save'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Passport 2026.pdf'), findsOneWidget);
    expect(find.text('Passport_scan.pdf'), findsNothing);
  });

  testWidgets('back with items asks before discarding them', (tester) async {
    await showScreen(tester);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('Discard upload?'), findsOneWidget);
    expect(find.byType(FileUploadScreenV2), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.byType(FileUploadScreenV2), findsNothing);
  });

  Future<void> showLongLists(WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 520);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await showScreen(
      tester,
      uploadFiles: [for (var i = 0; i < 10; i++) File('/upload/f$i.pdf')],
      collections: [
        for (var i = 0; i < 30; i++) collection(i, 'Collection $i'),
      ],
    );
  }

  testWidgets('file list stops at both scroll boundaries on iOS', (
    tester,
  ) async {
    await showLongLists(tester);
    final card = find.byType(ListView);
    final scrollable = find.descendant(
      of: card,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    final gesture = await tester.startGesture(tester.getCenter(card));
    await gesture.moveBy(const Offset(0, 30));
    await gesture.moveBy(const Offset(0, 150));
    await tester.pump();
    expect(position.pixels, 0);
    await gesture.up();
    await tester.pumpAndSettle();

    await tester.drag(card, const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(position.pixels, position.maxScrollExtent);
    final endGesture = await tester.startGesture(tester.getCenter(card));
    await endGesture.moveBy(const Offset(0, -30));
    await endGesture.moveBy(const Offset(0, -150));
    await tester.pump();
    expect(position.pixels, position.maxScrollExtent);
    await endGesture.up();
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('long collection lists keep selection and Save reachable', (
    tester,
  ) async {
    await showLongLists(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Save').hitTestable(), findsOneWidget);
    final chips = find.byType(CollectionSelectionWidget);
    await tester.drag(chips, const Offset(0, -2000));
    await tester.pumpAndSettle();
    final lastChip = find.widgetWithText(TagChipComponent, 'Collection 29');
    expect(lastChip.hitTestable(), findsOneWidget);
    await tester.tap(lastChip);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TagChipComponent>(lastChip).state,
      TagChipComponentState.selected,
    );
  });
}
