import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ui/tools/similar_image_file_info.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader("packages/ente_components/Inter")
      ..addFont(
        rootBundle.load("packages/ente_components/fonts/Inter-Medium.ttf"),
      );
    await loader.load();
  });

  testWidgets("missing size keeps the filename without a size label", (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SimilarImageFileInfo(displayName: "photo.jpg", fileSize: null),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text("photo.jpg"), findsOneWidget);
    expect(find.text("0 bytes"), findsNothing);
  });

  testWidgets("known size retains its formatted label", (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SimilarImageFileInfo(
            displayName: "photo.jpg",
            fileSize: 1572864,
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text("photo.jpg"), findsOneWidget);
    expect(find.text("1.50 MB"), findsOneWidget);
  });

  testWidgets("missing size preserves thumbnail and filename alignment", (
    tester,
  ) async {
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: Scaffold(
              body: Row(
                children: [
                  for (final size in <int?>[null, 1572864])
                    SizedBox(
                      width: 140,
                      height: 220,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: SizedBox.expand(key: ValueKey(size))),
                          const SizedBox(height: 6),
                          SimilarImageFileInfo(
                            displayName: size == null
                                ? "unknown.jpg"
                                : "known.jpg",
                            fileSize: size,
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byKey(const ValueKey<int?>(null))).height,
        tester.getSize(find.byKey(const ValueKey<int?>(1572864))).height,
        reason: "Thumbnail heights must match at text scale $scale",
      );
      expect(
        tester.getTopLeft(find.text("unknown.jpg")).dy,
        tester.getTopLeft(find.text("known.jpg")).dy,
        reason: "Filenames must align at text scale $scale",
      );
    }
  });
}
