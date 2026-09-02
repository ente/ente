import "dart:typed_data";

import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/core/cache/thumbnail_in_memory_cache.dart";
import "package:photos/core/constants.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/ui/viewer/gallery/component/gallery_file_widget.dart";
import "package:photos/ui/viewer/gallery/state/gallery_context_state.dart";
import "package:shared_preferences/shared_preferences.dart";

// A minimal valid 1x1 RGBA PNG.
const _tinyImage = <int>[
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    ServiceLocator.instance.init(
      await SharedPreferences.getInstance(),
      Dio(),
      Dio(),
      Dio(),
      PackageInfo(
        appName: "Photos",
        packageName: "photos",
        version: "1.0.0",
        buildNumber: "1",
      ),
    );
  });

  testWidgets("a thumbnail tier change recreates the thumbnail loader", (
    tester,
  ) async {
    final file = EnteFile()
      ..generatedID = 1
      ..fileType = FileType.image
      ..title = "photo.jpg";

    Widget buildGalleryTile(int thumbnailSize) {
      return MaterialApp(
        home: GalleryContextState(
          sortOrderAsc: false,
          child: SizedBox(
            width: 200,
            height: 200,
            child: GalleryFileWidget(
              key: const ValueKey("gallery-tile"),
              file: file,
              selectedFiles: null,
              limitSelectionToOne: true,
              tag: "gallery_",
              photoGridSize: photoGridSizeDefault,
              thumbnailSize: thumbnailSize,
              currentUserID: null,
            ),
          ),
        ),
      );
    }

    await tester.pumpWidget(buildGalleryTile(thumbnailSmallSize));
    final smallThumbnailState = tester.state<State<ThumbnailWidget>>(
      find.byType(ThumbnailWidget),
    );
    expect(
      tester
          .widget<ThumbnailWidget>(find.byType(ThumbnailWidget))
          .thumbnailSize,
      thumbnailSmallSize,
    );

    await tester.pumpWidget(buildGalleryTile(thumbnailLargeSize));
    final largeThumbnailState = tester.state<State<ThumbnailWidget>>(
      find.byType(ThumbnailWidget),
    );
    expect(
      tester
          .widget<ThumbnailWidget>(find.byType(ThumbnailWidget))
          .thumbnailSize,
      thumbnailLargeSize,
    );
    expect(largeThumbnailState, isNot(same(smallThumbnailState)));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets(
    "a requested large justified thumbnail bypasses the cached small tier",
    (tester) async {
      final file = EnteFile()
        ..generatedID = 2
        ..localID = "local-photo"
        ..fileType = FileType.image
        ..title = "local-photo.jpg";
      ThumbnailInMemoryLruCache.put(
        file,
        Uint8List.fromList(_tinyImage),
        thumbnailSmallSize,
      );
      addTearDown(() => ThumbnailInMemoryLruCache.clearCache(file));

      Widget buildGalleryTile({required bool justified}) {
        return MaterialApp(
          home: GalleryContextState(
            sortOrderAsc: false,
            child: SizedBox(
              width: 200,
              height: 200,
              child: GalleryFileWidget(
                file: file,
                selectedFiles: null,
                limitSelectionToOne: true,
                tag: justified ? "justified_" : "grid_",
                // A dense-grid size that preserves the legacy large-render /
                // small-local-cache behavior when no justified override exists.
                photoGridSize: photoGridSizeDefault - 1,
                thumbnailSize: justified ? thumbnailLargeSize : null,
                currentUserID: null,
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(buildGalleryTile(justified: true));
      final justifiedThumbnail = tester.widget<ThumbnailWidget>(
        find.byType(ThumbnailWidget),
      );
      expect(justifiedThumbnail.thumbnailSize, thumbnailLargeSize);
      expect(justifiedThumbnail.useRequestedThumbnailSizeForLocalCache, isTrue);
      expect(
        find.descendant(
          of: find.byType(ThumbnailWidget),
          matching: find.byType(Image),
        ),
        findsNothing,
      );

      await tester.pumpWidget(buildGalleryTile(justified: false));
      await tester.pump();
      final gridThumbnail = tester.widget<ThumbnailWidget>(
        find.byType(ThumbnailWidget),
      );
      expect(gridThumbnail.thumbnailSize, thumbnailLargeSize);
      expect(gridThumbnail.useRequestedThumbnailSizeForLocalCache, isFalse);
      expect(
        find.descendant(
          of: find.byType(ThumbnailWidget),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    },
  );
}
