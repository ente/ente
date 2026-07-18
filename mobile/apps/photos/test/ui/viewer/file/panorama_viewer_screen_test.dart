import "dart:async";
import "dart:io";
import "dart:typed_data";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:panorama/panorama.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/ui/viewer/file/panorama_viewer_screen.dart";

// A minimal valid 1x1 RGBA PNG, so Image.file/Image.memory can decode it.
const List<int> _tinyImage = [
  0x89,
  0x50,
  0x4e,
  0x47,
  0x0d,
  0x0a,
  0x1a,
  0x0a,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1f,
  0x15,
  0xc4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0d,
  0x49,
  0x44,
  0x41,
  0x54,
  0x08,
  0xd7,
  0x63,
  0xf8,
  0xcf,
  0xc0,
  0xf0,
  0x1f,
  0x00,
  0x05,
  0x00,
  0x01,
  0xff,
  0x89,
  0x99,
  0xd1,
  0x8d,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4e,
  0x44,
  0xae,
  0x42,
  0x60,
  0x82,
];

// GPano values of the Pixel 8a sample panorama from issue #11435.
const Map<String, String> _pixelXmp = {
  "GPano:CroppedAreaLeftPixels": "6183",
  "GPano:CroppedAreaTopPixels": "1040",
  "GPano:CroppedAreaImageWidthPixels": "2520",
  "GPano:CroppedAreaImageHeightPixels": "1664",
  "GPano:FullPanoWidthPixels": "8762",
  "GPano:FullPanoHeightPixels": "4381",
  "GPano:InitialViewHeadingDegrees": "305",
  "GPano:ProjectionType": "equirectangular",
};

void main() {
  late Directory tempDir;
  late File imageFile;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync("pano_viewer_test");
    imageFile = File("${tempDir.path}/pano.png")
      ..writeAsBytesSync(_tinyImage, flush: true);
  });

  tearDownAll(() {
    tempDir.deleteSync(recursive: true);
  });

  Widget wrap(Widget child) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
  }

  testWidgets(
    "builds Panorama only after XMP is parsed, with the final crop values",
    (tester) async {
      final completer = Completer<Map<String, String>>();

      await tester.pumpWidget(
        wrap(
          PanoramaViewerScreen(
            file: imageFile,
            thumbnail: null,
            xmpExtractor: (_) => completer.future,
          ),
        ),
      );

      // Regression check for #11435: the Panorama widget must not exist yet.
      // Building it with placeholder crop values and updating them afterwards
      // makes the panorama package regenerate its sphere mesh, dropping the
      // already-loaded texture and rendering a blank (untextured) panorama.
      expect(find.byType(Panorama), findsNothing);

      completer.complete(_pixelXmp);
      await tester.pump();

      final pano = tester.widget<Panorama>(find.byType(Panorama));
      expect(pano.croppedArea, const Rect.fromLTWH(6183, 1040, 2520, 1664));
      expect(pano.croppedFullWidth, 8762);
      expect(pano.croppedFullHeight, 4381);
      // The initial view must face the cropped area (compass heading 305.8
      // degrees maps to longitude 54.19), not the canvas edge.
      expect(pano.longitude, closeTo(54.19, 0.01));

      // Let the auto-hide timer fire and dispose the screen.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets("falls back to a full-sphere mapping when XMP is unavailable", (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        PanoramaViewerScreen(
          file: imageFile,
          thumbnail: null,
          xmpExtractor: (_) async => throw StateError("no xmp"),
        ),
      ),
    );
    await tester.pump();

    final pano = tester.widget<Panorama>(find.byType(Panorama));
    expect(pano.croppedArea, const Rect.fromLTWH(0, 0, 1, 1));
    expect(pano.croppedFullWidth, 1.0);
    expect(pano.croppedFullHeight, 1.0);
    expect(pano.longitude, 0.0);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("shows the thumbnail while XMP is being parsed", (tester) async {
    final completer = Completer<Map<String, String>>();
    final thumbnail = Uint8List.fromList(_tinyImage);

    await tester.pumpWidget(
      wrap(
        PanoramaViewerScreen(
          file: imageFile,
          thumbnail: thumbnail,
          xmpExtractor: (_) => completer.future,
        ),
      ),
    );

    expect(find.byType(Panorama), findsNothing);
    expect(find.byType(Image), findsOneWidget);

    completer.complete(const {});
    await tester.pump();
    expect(find.byType(Panorama), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox());
  });
}
