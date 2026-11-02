import 'dart:io';

import 'package:ente_components/ente_components.dart';
import 'package:ente_sharing/models/user.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/services/collections/models/collection.dart';
import 'package:locker/services/configuration.dart';
import 'package:locker/ui/components/add_to_collection_sheet.dart';

import '../../test_utils/configuration_test_util.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await setupLockerConfigurationForTest('restore_picker');
    await Configuration.instance.setUserID(1);
  });

  tearDown(() async {
    clearLockerConfigurationTestHandlers();
    await root.delete(recursive: true);
  });

  for (final allowMultiple in [false, true]) {
    testWidgets(
      'collection picker ${allowMultiple ? 'keeps multiple destinations by default' : 'replaces the restore destination'}',
      (tester) async {
        AddToCollectionSheetResult? result;
        final collections = [_collection(1, 'A'), _collection(2, 'B')];
        await tester.pumpWidget(
          MaterialApp(
            theme: ComponentTheme.lightTheme(app: ComponentApp.locker),
            localizationsDelegates: StringsLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('en')],
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = allowMultiple
                        ? await showAddToCollectionSheet(
                            context,
                            collections: collections,
                          )
                        : await showAddToCollectionSheet(
                            context,
                            collections: collections,
                            allowMultiple: false,
                          );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<ButtonComponent>(find.byType(ButtonComponent)).onTap,
          isNull,
        );
        await tester.tap(find.text('A'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('B'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widgetList<TagChipComponent>(find.byType(TagChipComponent))
              .where((chip) => chip.state == TagChipComponentState.selected)
              .map((chip) => chip.label),
          allowMultiple ? ['A', 'B'] : ['B'],
        );
        if (!allowMultiple) {
          await tester.tap(find.text('B'));
          await tester.pumpAndSettle();
          expect(
            tester.widget<ButtonComponent>(find.byType(ButtonComponent)).onTap,
            isNull,
          );
          await tester.tap(find.text('B'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(
          result!.selectedCollections.map((c) => c.id),
          allowMultiple ? [1, 2] : [2],
        );
      },
    );
  }
}

Collection _collection(int id, String name) => Collection(
  id,
  User(id: 1, email: 'test@example.com'),
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
