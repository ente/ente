import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photos/ente_theme_data.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/ui/components/collection_share_badge.dart';
import 'package:photos/ui/sharing/share_components.dart';
import 'package:photos/ui/sharing/widgets/participant_role_sheet.dart';

void main() {
  testWidgets(
    'shows current role without descriptions and returns the choice',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      ParticipantRoleAction? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: lightThemeData,
          localizationsDelegates: StringsLocalizations.localizationsDelegates,
          supportedLocales: StringsLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showParticipantRoleSheet(
                    context,
                    email: 'a.long.participant.address@example.com',
                    currentRole: CollectionParticipantRole.collaborator,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      for (final entry in {
        'Viewer': ParticipantRoleAction.viewer,
        'Collaborator': ParticipantRoleAction.collaborator,
        'Admin': ParticipantRoleAction.admin,
        'Remove from album': ParticipantRoleAction.remove,
      }.entries) {
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.widgetWithText(ShareMenuItem, 'Collaborator'),
            matching: find.byType(CollectionSelectedBadge),
          ),
          findsOneWidget,
        );
        for (final item in tester.widgetList<ShareMenuItem>(
          find.byType(ShareMenuItem),
        )) {
          expect(item.subtitle, isNull);
        }
        await tester.ensureVisible(find.text(entry.key));
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        expect(result, entry.value);
        expect(find.byType(BottomSheetComponent), findsNothing);
        expect(tester.takeException(), isNull);
      }

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    },
  );
}
