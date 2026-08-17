import "dart:async";
import "dart:io";
import "dart:typed_data";

import "package:ente_panorama_viewer/ente_panorama_viewer.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:hugeicons/hugeicons.dart";
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
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      supportedLocales: StringsLocalizations.supportedLocales,
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
            motionAvailabilityChecker: () async => false,
          ),
        ),
      );

      expect(find.byType(EntePanoramaViewer), findsNothing);

      completer.complete(_pixelXmp);
      await tester.pump();

      final pano = tester.widget<EntePanoramaViewer>(
        find.byType(EntePanoramaViewer),
      );
      expect(
        pano.geometry,
        PanoramaGeometry(
          fullSize: const Size(8762, 4381),
          croppedArea: const Rect.fromLTWH(6183, 1040, 2520, 1664),
        ),
      );
      // The initial view must face the cropped area (compass heading 305.8
      // degrees maps to longitude 125.81 because the panorama widget's
      // longitude 0 faces the horizontal center), not the empty canvas area.
      expect(pano.initialView!.longitude, closeTo(125.81, 0.01));
      expect(pano.initialView!.latitude, closeTo(13.09, 0.01));

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
          motionAvailabilityChecker: () async => false,
        ),
      ),
    );
    await tester.pump();

    final pano = tester.widget<EntePanoramaViewer>(
      find.byType(EntePanoramaViewer),
    );
    expect(pano.geometry, const PanoramaGeometry.fullSphere());
    expect(pano.initialView!.longitude, 0);

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
          motionAvailabilityChecker: () async => false,
        ),
      ),
    );

    expect(find.byType(EntePanoramaViewer), findsNothing);
    expect(find.byType(Image), findsOneWidget);

    completer.complete(const {});
    await tester.pump();
    expect(find.byType(EntePanoramaViewer), findsOneWidget);

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets("shows and toggles motion only when it is available", (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        PanoramaViewerScreen(
          file: imageFile,
          thumbnail: null,
          xmpExtractor: (_) async => _pixelXmp,
          motionAvailabilityChecker: () async => true,
        ),
      ),
    );
    await tester.pump();

    final motionIcon = find.byType(HugeIcon);
    expect(motionIcon, findsOneWidget);
    expect(
      tester.widget<HugeIcon>(motionIcon).icon,
      same(HugeIcons.strokeRoundedNavigation05),
    );
    await tester.tap(motionIcon);
    await tester.pump();

    final pano = tester.widget<EntePanoramaViewer>(
      find.byType(EntePanoramaViewer),
    );
    expect(pano.motionEnabled, isTrue);
    expect(
      tester.widget<HugeIcon>(motionIcon).icon,
      same(HugeIcons.strokeRoundedNavigationOff),
    );

    await tester.pump(const Duration(seconds: 6));
    await tester.pumpWidget(const SizedBox());
  });
}
