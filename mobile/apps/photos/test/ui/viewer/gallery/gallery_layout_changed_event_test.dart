import "package:dio/dio.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/events/gallery_layout_changed_event.dart";
import "package:photos/models/file/dummy_file.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/file_load_result.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/service_locator.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/ui/viewer/gallery/component/group/group_header_widget.dart";
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

    // GalleryGroups only needs Configuration's preferences-backed user ID.
    // Plugin initialization is unavailable in a widget-test process.
    try {
      await Configuration.instance.init(preferences);
    } catch (_) {}

    // Construct the delayed flag refresher outside the widget-test fake clock.
    expect(flagService.internalUser, isTrue);
  });

  setUp(() async {
    await localSettings.setInternalUserDisabled(false);
  });

  tearDown(() async {
    await localSettings.setInternalUserDisabled(false);
  });

  testWidgets(
    "layout changes rebuild every mounted gallery without loading files",
    (tester) async {
      await localSettings.setPhotoGridSize(4);
      final firstKey = GlobalKey<GalleryState>();
      final secondKey = GlobalKey<GalleryState>();
      var firstLoadCount = 0;
      var secondLoadCount = 0;
      final firstFile = _dummyFile("first");
      final secondFile = _dummyFile("second");

      await tester.pumpWidget(
        MaterialApp(
          theme: lightThemeData,
          localizationsDelegates: StringsLocalizations.localizationsDelegates,
          supportedLocales: StringsLocalizations.supportedLocales,
          home: Column(
            children: [
              Expanded(
                child: _galleryHost(
                  Gallery(
                    key: firstKey,
                    asyncLoader: (start, end, {limit, asc}) async {
                      firstLoadCount++;
                      return FileLoadResult([firstFile], false);
                    },
                    tagPrefix: "first_",
                    limitSelectionToOne: true,
                    showSelectAll: false,
                  ),
                ),
              ),
              Expanded(
                child: _galleryHost(
                  Gallery(
                    key: secondKey,
                    asyncLoader: (start, end, {limit, asc}) async {
                      secondLoadCount++;
                      return FileLoadResult([secondFile], false);
                    },
                    tagPrefix: "second_",
                    limitSelectionToOne: true,
                    showSelectAll: false,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 750));
      await tester.pump();

      final firstGroups = firstKey.currentState!.galleryGroups!;
      final secondGroups = secondKey.currentState!.galleryGroups!;
      final oldHeaderExtent = firstGroups.groupHeaderExtent;
      expect(firstGroups.crossAxisCount, 4);
      expect(secondGroups.crossAxisCount, 4);
      expect(firstLoadCount, 1);
      expect(secondLoadCount, 1);

      await localSettings.setPhotoGridSize(6);
      Bus.instance.fire(GalleryLayoutChangedEvent());
      await tester.pumpAndSettle();

      final updatedFirstGroups = firstKey.currentState!.galleryGroups!;
      final updatedSecondGroups = secondKey.currentState!.galleryGroups!;
      expect(updatedFirstGroups, isNot(same(firstGroups)));
      expect(updatedSecondGroups, isNot(same(secondGroups)));
      expect(updatedFirstGroups.crossAxisCount, 6);
      expect(updatedSecondGroups.crossAxisCount, 6);
      expect(
        updatedFirstGroups.groupHeaderExtent,
        greaterThan(oldHeaderExtent),
      );
      expect(
        updatedSecondGroups.groupHeaderExtent,
        greaterThan(oldHeaderExtent),
      );
      expect(updatedFirstGroups.allFiles.single, same(firstFile));
      expect(updatedSecondGroups.allFiles.single, same(secondFile));
      expect(firstLoadCount, 1);
      expect(secondLoadCount, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets("a deep layout change preserves partial-row progress", (
    tester,
  ) async {
    await localSettings.setGalleryLayoutType(GalleryLayoutType.grid);
    await localSettings.setPhotoGridSize(2);
    final galleryKey = GlobalKey<GalleryState>();
    final files = List<EnteFile>.generate(1000, _justifiedTestFile);

    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        home: Scaffold(
          body: _galleryHost(
            Gallery(
              key: galleryKey,
              asyncLoader: (start, end, {limit, asc}) async =>
                  FileLoadResult(files, false),
              tagPrefix: "anchor_",
              enableFileGrouping: false,
              limitSelectionToOne: true,
              showSelectAll: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pump();

    final oldGroups = galleryKey.currentState!.galleryGroups!;
    final anchorFile = files[800];
    final oldGeometry = oldGroups.getGeometryOfFile(anchorFile)!;
    const rowProgress = 0.72;
    final oldAnchorOffset =
        oldGeometry.rowOffset + oldGeometry.rowExtent * rowProgress;
    final scrollableFinder = find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    );
    expect(scrollableFinder, findsOneWidget);
    final scrollPosition = tester
        .state<ScrollableState>(scrollableFinder)
        .position;
    scrollPosition.jumpTo(oldAnchorOffset);
    await tester.pump();
    expect(
      oldGroups.getFileAtScrollOffset(scrollPosition.pixels),
      same(anchorFile),
    );

    await Future.wait([
      localSettings.setGalleryLayoutType(GalleryLayoutType.justified),
      localSettings.setPhotoGridSize(6),
    ]);
    Bus.instance.fire(GalleryLayoutChangedEvent());
    await tester.pump();
    await tester.pump();
    await tester.pump();

    final justifiedGroups = galleryKey.currentState!.galleryGroups!;
    expect(justifiedGroups.layoutType, GalleryLayoutType.justified);
    final newGeometry = justifiedGroups.getGeometryOfFile(anchorFile)!;
    expect(newGeometry.rowExtent, lessThan(oldGeometry.rowExtent));
    final expectedAnchorOffset =
        newGeometry.rowOffset + newGeometry.rowExtent * rowProgress;
    expect(
      (newGeometry.rowOffset - oldGeometry.rowOffset).abs(),
      greaterThan(500),
      reason: "the two layouts should have meaningfully different geometry",
    );
    expect(scrollPosition.pixels, closeTo(expectedAnchorOffset, 0.001));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RepaintBoundary &&
            widget.key == ValueKey("anchor_${anchorFile.tag}"),
      ),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await localSettings.setGalleryLayoutType(GalleryLayoutType.grid);
    await localSettings.setPhotoGridSize(4);
  });

  testWidgets(
    "a non-home layout change preserves progress below its pinned header",
    (tester) async {
      await localSettings.setGalleryLayoutType(GalleryLayoutType.grid);
      await localSettings.setPhotoGridSize(6);
      final galleryKey = GlobalKey<GalleryState>();
      final files = List<EnteFile>.generate(180, _justifiedTestFile);
      const galleryHeaderHeight = 32.0;
      const appBarExpandedHeight = 92.0;
      const appBarCollapsedHeight = kToolbarHeight;
      final appBar = GalleryAppBarConfig(
        sliverBuilder: (_) => const SliverAppBarComponent(
          title: "Album",
          expandedHeight: appBarExpandedHeight,
          collapsedHeight: appBarCollapsedHeight,
        ),
        geometryBuilder: (context) => SliverAppBarComponent.resolveGeometry(
          context,
          expandedHeight: appBarExpandedHeight,
          collapsedHeight: appBarCollapsedHeight,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: lightThemeData,
          localizationsDelegates: StringsLocalizations.localizationsDelegates,
          supportedLocales: StringsLocalizations.supportedLocales,
          home: Scaffold(
            body: _galleryHost(
              Gallery(
                key: galleryKey,
                appBar: appBar,
                asyncLoader: (start, end, {limit, asc}) async =>
                    FileLoadResult(files, false),
                tagPrefix: "pinned_anchor_",
                groupType: GroupType.month,
                limitSelectionToOne: true,
                showSelectAll: false,
                header: const SizedBox(
                  key: Key("gallery_header"),
                  height: galleryHeaderHeight,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 750));
      await tester.pump();

      final oldGroups = galleryKey.currentState!.galleryGroups!;
      final appBarGeometry = appBar.resolveGeometry(galleryKey.currentContext!);
      expect(appBarGeometry.minExtent, greaterThan(0));
      expect(appBarGeometry.collapseExtent, greaterThan(0));
      expect(
        tester.getSize(find.byKey(const Key("gallery_header"))).height,
        galleryHeaderHeight,
      );
      final anchorFile = files[120];
      final oldGeometry = oldGroups.getGeometryOfFile(anchorFile)!;
      const rowProgress = 0.35;
      final oldAnchorOffset =
          appBarGeometry.collapseExtent +
          galleryHeaderHeight +
          oldGeometry.rowOffset +
          oldGeometry.rowExtent * rowProgress -
          oldGroups.groupHeaderExtent;
      final scrollableFinder = find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      );
      expect(scrollableFinder, findsOneWidget);
      final scrollPosition = tester
          .state<ScrollableState>(scrollableFinder)
          .position;
      scrollPosition.jumpTo(oldAnchorOffset);
      await tester.pump();

      final pinnedHeaderFinder = find.byWidgetPredicate(
        (widget) => widget is GroupHeaderWidget && widget.isPinnedHeader,
      );
      expect(pinnedHeaderFinder, findsOneWidget);
      expect(
        tester.getTopLeft(pinnedHeaderFinder).dy,
        closeTo(appBarGeometry.minExtent, 0.001),
      );
      expect(
        oldGroups.getFileAtScrollOffset(
          scrollPosition.pixels -
              appBarGeometry.collapseExtent -
              galleryHeaderHeight +
              oldGroups.groupHeaderExtent,
        ),
        same(anchorFile),
      );

      await localSettings.setPhotoGridSize(2);
      Bus.instance.fire(GalleryLayoutChangedEvent());
      await tester.pumpAndSettle();

      final newGroups = galleryKey.currentState!.galleryGroups!;
      final newGeometry = newGroups.getGeometryOfFile(anchorFile)!;
      final expectedAnchorOffset =
          appBarGeometry.collapseExtent +
          galleryHeaderHeight +
          newGeometry.rowOffset +
          newGeometry.rowExtent * rowProgress -
          newGroups.groupHeaderExtent;
      expect(newGroups.groupHeaderExtent, isNot(oldGroups.groupHeaderExtent));
      expect(scrollPosition.pixels, closeTo(expectedAnchorOffset, 0.001));
      expect(
        newGroups.getFileAtScrollOffset(
          scrollPosition.pixels -
              appBarGeometry.collapseExtent -
              galleryHeaderHeight +
              newGroups.groupHeaderExtent,
        ),
        same(anchorFile),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      await localSettings.setPhotoGridSize(4);
    },
  );
}

Widget _galleryHost(Gallery gallery) {
  return GalleryBoundariesProvider(child: GalleryFilesState(child: gallery));
}

DummyFile _dummyFile(String groupID) {
  return DummyFile(groupID: groupID, index: 0)
    ..creationTime = DateTime(2026, 8, 19).microsecondsSinceEpoch;
}

DummyFile _justifiedTestFile(int index) {
  final dimensions = switch (index % 4) {
    0 => (w: 1600, h: 900),
    1 => (w: 900, h: 1600),
    2 => (w: 1200, h: 1200),
    _ => (w: 2400, h: 1000),
  };
  return DummyFile(groupID: "anchor", index: index)
    // Real libraries commonly contain many files with the same EXIF second.
    ..creationTime = DateTime(2026, 8, 19).microsecondsSinceEpoch
    ..fileType = FileType.image
    ..pubMagicMetadata = PubMagicMetadata(w: dimensions.w, h: dimensions.h);
}
