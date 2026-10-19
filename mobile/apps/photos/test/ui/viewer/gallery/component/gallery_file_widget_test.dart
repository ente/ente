import "dart:typed_data";

import "package:dio/dio.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/core/cache/thumbnail_in_memory_cache.dart";
import "package:photos/core/constants.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/viewer/file/gallery_photo_page_route.dart";
import "package:photos/ui/viewer/file/hero_image.dart";
import "package:photos/ui/viewer/file/image_zoom/image_zoom_viewer.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/ui/viewer/gallery/component/gallery_file_widget.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_context_state.dart";
import "package:photos/ui/viewer/gallery/swipe_selection_wrapper.dart";
import "package:photos/ui/viewer/gallery/swipe_to_select_helper.dart";
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
  0x72,
  0x9c,
  0x52,
  0x67,
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

  for (final startWithLongPress in [true, false]) {
    testWidgets(
      startWithLongPress
          ? "long press starts swipe selection before crossing is enabled"
          : "horizontal movement enables crossing for an existing selection",
      (tester) async {
        final files = List.generate(
          3,
          (index) => EnteFile()
            ..generatedID = index + 10
            ..fileType = FileType.image
            ..title = "photo-$index.jpg",
        );
        final selectedFiles = SelectedFiles();
        final swipeHelper = SwipeToSelectHelper(
          allFiles: files,
          selectedFiles: selectedFiles,
        );
        final swipeActive = ValueNotifier(false);
        final controller = ScrollController();
        if (!startWithLongPress) selectedFiles.selectAll({files.first});
        await tester.pumpWidget(
          MaterialApp(
            home: GalleryBoundariesProvider(
              child: GalleryContextState(
                sortOrderAsc: false,
                child: SwipeSelectionWrapper(
                  swipeHelper: swipeHelper,
                  selectedFiles: selectedFiles,
                  isEnabled: true,
                  swipeActiveNotifier: swipeActive,
                  scrollController: controller,
                  child: Align(
                    alignment: Alignment.topLeft,
                    child: Row(
                      children: files.map((file) {
                        return SizedBox(
                          width: 100,
                          height: 100,
                          child: GalleryFileWidget(
                            file: file,
                            selectedFiles: selectedFiles,
                            limitSelectionToOne: false,
                            tag: "selection_",
                            photoGridSize: photoGridSizeDefault,
                            currentUserID: null,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        final gesture = await tester.startGesture(
          Offset(startWithLongPress ? 50 : 150, 50),
        );
        if (startWithLongPress) {
          await tester.pump(const Duration(milliseconds: 600));
          expect(swipeHelper.isActive, isTrue);
          expect(swipeActive.value, isFalse);
        } else {
          await gesture.moveBy(const Offset(20, 0));
          // No pump: the same pointer event that activates swipe mode must
          // reach the starting tile before the next widget rebuild.
          expect(swipeActive.value, isTrue);
          expect(swipeHelper.isActive, isTrue);
          expect(selectedFiles.files, containsAll([files.first, files[1]]));
        }
        await gesture.moveTo(const Offset(250, 50));
        expect(selectedFiles.files, containsAll(files));
        await gesture.up();
        await tester.pump();
        expect(swipeActive.value, isFalse);
        expect(swipeHelper.isActive, isFalse);

        // A later vertical gallery drag must not reactivate swipe selection.
        final scrollGesture = await tester.startGesture(const Offset(150, 50));
        await scrollGesture.moveBy(const Offset(0, 30));
        expect(swipeActive.value, isFalse);
        expect(swipeHelper.isActive, isFalse);
        expect(selectedFiles.files, containsAll(files));
        await scrollGesture.up();

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
        swipeHelper.dispose();
        selectedFiles.dispose();
        swipeActive.dispose();
        controller.dispose();
      },
    );
  }

  testWidgets("Grid thumbnail tiers and overrides recreate the loader", (
    tester,
  ) async {
    final file = EnteFile()
      ..generatedID = 1
      ..fileType = FileType.image
      ..title = "photo.jpg";

    Widget buildGalleryTile({required int gridSize, int? thumbnailSize}) {
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
              photoGridSize: gridSize,
              thumbnailSize: thumbnailSize,
              currentUserID: null,
            ),
          ),
        ),
      );
    }

    for (final useOverride in [false, true]) {
      await tester.pumpWidget(
        buildGalleryTile(
          gridSize: useOverride ? 3 : 4,
          thumbnailSize: useOverride ? thumbnailSmallSize : null,
        ),
      );
      final smallThumbnailState = tester.state<State<ThumbnailWidget>>(
        find.byType(ThumbnailWidget),
      );
      expect(
        tester
            .widget<ThumbnailWidget>(find.byType(ThumbnailWidget))
            .thumbnailSize,
        thumbnailSmallSize,
      );

      await tester.pumpWidget(
        buildGalleryTile(
          gridSize: 3,
          thumbnailSize: useOverride ? thumbnailLargeSize : null,
        ),
      );
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
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets(
    "a justified thumbnail keeps its decoded image through the return hero",
    (tester) async {
      final file = EnteFile()
        ..generatedID = 3
        ..localID = "hero-photo"
        ..fileType = FileType.image
        ..title = "hero-photo.jpg";
      final bytes = Uint8List.fromList(_tinyImage);
      ThumbnailInMemoryLruCache.put(file, bytes, thumbnailLargeSize);
      addTearDown(() => ThumbnailInMemoryLruCache.clearCache(file));
      await tester.pumpWidget(
        MaterialApp(
          home: GalleryContextState(
            sortOrderAsc: false,
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 200,
                height: 120,
                child: GalleryFileWidget(
                  file: file,
                  selectedFiles: null,
                  limitSelectionToOne: true,
                  tag: "gallery_",
                  photoGridSize: photoGridSizeDefault,
                  thumbnailSize: thumbnailLargeSize,
                  currentUserID: null,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await precacheImage(
          MemoryImage(bytes),
          tester.element(find.byType(GalleryFileWidget)),
        );
      });
      await tester.pump();
      final thumbnail = find.byType(ThumbnailWidget, skipOffstage: false);
      final thumbnailState = tester.state<State<ThumbnailWidget>>(thumbnail);
      final hero = find.byType(Hero);
      final tag = tester.widget<Hero>(hero).tag;
      final sourceImage = imageFromHero(tester.element(hero));
      expect(sourceImage, isNotNull);
      final navigator = Navigator.of(tester.element(hero));
      navigator.push(
        GalleryPhotoPageRoute<void>(
          tag: tag,
          sourceImage: sourceImage,
          page: ImageZoomViewer(
            imageProvider: MemoryImage(bytes),
            heroTag: tag,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.state(thumbnail), same(thumbnailState));
      ThumbnailInMemoryLruCache.clearCache(file);
      PaintingBinding.instance.imageCache.clear();

      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.state(thumbnail), same(thumbnailState));
      expect(imageFromHero(thumbnailState.context), isNotNull);
      await tester.pump(const Duration(milliseconds: 110));
      expect(tester.state(thumbnail), same(thumbnailState));
      expect(imageFromHero(thumbnailState.context), isNotNull);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    },
  );

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
