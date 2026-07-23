import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/ui/actions/collection/collection_sharing_actions.dart";
import "package:styled_text/styled_text.dart";

void main() {
  group("CollectionActions", () {
    testWidgets("album delete body uses light theme text colors", (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: lightThemeData,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return TextButton(
                  onPressed: () async {
                    await CollectionActions(
                      CollectionsService.instance,
                    ).deleteMultipleCollectionSheet(context, [_collection()]);
                  },
                  child: const Text("Delete albums"),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text("Delete albums"));
      await tester.pumpAndSettle();

      final colors = ComponentTheme.colorsForApp(
        ComponentApp.photos,
        brightness: Brightness.light,
      );
      final body = tester.widget<StyledText>(find.byType(StyledText));
      final boldTag = body.tags["bold"]! as StyledTextTag;
      expect(body.style, TextStyles.body.copyWith(color: colors.textLight));
      expect(boldTag.style, TextStyles.body.copyWith(color: colors.textBase));
    });
  });
}

Collection _collection() {
  return Collection(
    1,
    User(id: 1, email: "owner@example.com"),
    "",
    null,
    "Album",
    null,
    null,
    CollectionType.album,
    CollectionAttributes(),
    const [],
    const [],
    0,
  );
}
