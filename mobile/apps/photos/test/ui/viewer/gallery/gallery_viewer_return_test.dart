import "dart:convert";

import "package:dio/dio.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/app_mode.dart";
import "package:photos/core/cache/thumbnail_in_memory_cache.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/constants.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/file_load_result.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/service_locator.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:photos/ui/viewer/file/hero_image.dart";
import "package:photos/ui/viewer/gallery/component/gallery_file_widget.dart";
import "package:photos/ui/viewer/gallery/component/group/type.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/gallery_app_bar_config.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    ServiceLocator.instance.init(
      preferences,
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
    await localSettings.setAppMode(AppMode.localGallery);
    try {
      await Configuration.instance.init(preferences);
    } catch (_) {}
  });

  for (final layout in GalleryLayoutType.values) {
    testWidgets("$layout returns to the current photo with a hero flight", (
      tester,
    ) async {
      await localSettings.setGalleryLayoutType(layout);
      await localSettings.setPhotoGridSize(4);
      final bytes = base64Decode(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQI12P4z8DwHwAFAAH/cpxSZwAAAABJRU5ErkJggg==",
      );
      final files = List.generate(
        180,
        (index) => EnteFile()
          ..generatedID = index + 1
          ..creationTime = DateTime(2026, 10, 14).microsecondsSinceEpoch
          ..fileType = FileType.image
          ..title = "photo-$index.jpg"
          ..pubMagicMetadata = PubMagicMetadata(
            w: index.isEven ? 1600 : 900,
            h: 1200,
          ),
      );
      for (final file in files) {
        ThumbnailInMemoryLruCache.put(file, bytes, thumbnailLargeSize);
        ThumbnailInMemoryLruCache.put(file, bytes, thumbnailSmallSize);
      }
      addTearDown(ThumbnailInMemoryLruCache.clearAll);
      final galleryKey = GlobalKey<GalleryState>();
      final appBar = GalleryAppBarConfig(
        sliverBuilder: (_) => const SliverAppBarComponent(
          title: "Album",
          expandedHeight: 92,
          collapsedHeight: kToolbarHeight,
        ),
        geometryBuilder: (context) => SliverAppBarComponent.resolveGeometry(
          context,
          expandedHeight: 92,
          collapsedHeight: kToolbarHeight,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: lightThemeData,
          localizationsDelegates: StringsLocalizations.localizationsDelegates,
          supportedLocales: StringsLocalizations.supportedLocales,
          home: Scaffold(
            body: GalleryBoundariesProvider(
              child: GalleryFilesState(
                child: Gallery(
                  key: galleryKey,
                  appBar: appBar,
                  asyncLoader: (start, end, {limit, asc}) async =>
                      FileLoadResult(files, false),
                  tagPrefix: "return_",
                  groupType: GroupType.month,
                  header: const SizedBox(height: 32),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await precacheImage(MemoryImage(bytes), galleryKey.currentContext!);
      });
      await tester.pump();
      final gallery = galleryKey.currentState!;
      final scrollPosition = tester
          .state<ScrollableState>(
            find.descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            ),
          )
          .position;
      final initialOffset = scrollPosition.pixels;
      gallery.revealFile(files.first);
      expect(scrollPosition.pixels, initialOffset);

      var scrollChanges = 0;
      scrollPosition.addListener(() => scrollChanges++);
      await tester.tap(find.byType(GalleryFileWidget).first);
      await tester.pumpAndSettle();
      final pages = tester.widget<PageView>(find.byType(PageView));
      for (final index in [30, 80, 140]) {
        pages.controller!.jumpToPage(index);
        await tester.pumpAndSettle();
        expect(scrollPosition.pixels, initialOffset);
        expect(scrollChanges, 0);
      }
      final target = files[140];
      Finder targetTile() => find.byWidgetPredicate(
        (widget) => widget is GalleryFileWidget && widget.file == target,
        skipOffstage: false,
      );
      expect(targetTile(), findsNothing);

      await tester.binding.handlePopRoute();
      expect(scrollChanges, 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(HeroFlightImage), findsOneWidget);
      expect(
        tester.widget<HeroFlightImage>(find.byType(HeroFlightImage)).image,
        isNotNull,
      );
      expect(targetTile(), findsOneWidget);
      final tileRect = tester.getRect(targetTile());
      final pinnedHeight =
          appBar.resolveGeometry(galleryKey.currentContext!).minExtent +
          gallery.galleryGroups!.groupHeaderExtent;
      expect(tileRect.top, greaterThanOrEqualTo(pinnedHeight));
      expect(
        tileRect.bottom,
        lessThanOrEqualTo(scrollPosition.viewportDimension),
      );
      final returnOffset = scrollPosition.pixels;
      await tester.pumpAndSettle();
      expect(scrollPosition.pixels, returnOffset);
      expect(find.byType(DetailPage), findsNothing);

      gallery.revealFile(target.copyWith());
      expect(scrollPosition.pixels, returnOffset);
      gallery.revealFile(EnteFile()..generatedID = -1);
      expect(scrollPosition.pixels, returnOffset);
      gallery.revealFile(files.first);
      await tester.pumpAndSettle();
      final firstTile = find.byWidgetPredicate(
        (widget) => widget is GalleryFileWidget && widget.file == files.first,
      );
      expect(
        tester.getTopLeft(firstTile).dy,
        greaterThanOrEqualTo(pinnedHeight),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    });
  }
}
