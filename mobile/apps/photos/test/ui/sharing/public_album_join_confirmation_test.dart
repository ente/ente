import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/ui/sharing/widgets/public_album_join_confirmation.dart";

void main() {
  testWidgets("public join requires explicit confirmation of owner approval", (
    tester,
  ) async {
    bool? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: StringsLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                confirmed = await showPublicAlbumJoinConfirmation(context);
              },
              child: const Text("Open confirmation"),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text("Open confirmation"));
    await tester.pumpAndSettle();
    expect(find.text("Join album?"), findsOneWidget);
    expect(
      find.text(
        "Albums shared with you by this album’s owner will be approved automatically.",
      ),
      findsOneWidget,
    );
    expect(confirmed, isNull);

    await tester.tap(find.text("Cancel"));
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);

    await tester.tap(find.text("Open confirmation"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Join"));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });
}
