import "dart:async";
import "dart:typed_data" show Uint32List;

import "package:dio/dio.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_rust_bridge/flutter_rust_bridge.dart" show Int64List;
import "package:flutter_test/flutter_test.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/events/collection_meta_event.dart";
import "package:photos/events/gallery_layout_changed_event.dart";
import "package:photos/models/file/dummy_file.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_sort_order.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/file_load_result.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/service_locator.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/src/rust/frb_generated.dart";
import "package:photos/ui/settings/gallery_settings_screen.dart";
import "package:photos/ui/viewer/gallery/component/group/group_header_widget.dart";
import "package:photos/ui/viewer/gallery/component/group/type.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/gallery_app_bar_config.dart";
import "package:photos/ui/viewer/gallery/layout_settings.dart";
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
  });

  setUp(() async {
    await localSettings.setGalleryLayoutType(GalleryLayoutType.grid);
  });

  testWidgets("filename sort loads the full album and restores date headers", (
    tester,
  ) async {
    final key = GlobalKey<GalleryState>();
    final api = _GalleryFileSortApi();
    EntePhotosRust.initMock(api: api);
    addTearDown(EntePhotosRust.dispose);
    var order = FileSortOrder.filenameAscending;
    final limits = <int?>[];
    final files = List.generate(
      201,
      (index) => _justifiedTestFile(index)
        ..title = "IMG${201 - index}.jpg"
        ..uploadedFileID = index + 1,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: StringsLocalizations.supportedLocales,
        home: Scaffold(
          body: _galleryHost(
            Gallery(
              key: key,
              tagPrefix: "filename_sort",
              groupType: GroupType.day,
              sortOrderFn: () => order,
              forceReloadEvents: [Bus.instance.on<CollectionMetaEvent>()],
              limitSelectionToOne: true,
              showSelectAll: false,
              asyncLoader: (start, end, {limit, asc}) async {
                limits.add(limit);
                return FileLoadResult(List<EnteFile>.from(files), false);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(limits, [null]);
    expect(key.currentState!.galleryGroups!.allFiles, hasLength(201));
    expect(key.currentState!.galleryGroups!.allFiles.first.title, "IMG1.jpg");
    expect(key.currentState!.galleryGroups!.groupType, GroupType.none);

    final pendingSort = Completer<void>();
    api.nextCall = pendingSort;
    order = FileSortOrder.filenameAscending;
    Bus.instance.fire(
      CollectionMetaEvent(1, CollectionMetaEventType.sortChanged),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(api.nextCall, isNull);

    order = FileSortOrder.oldestFirst;
    Bus.instance.fire(
      CollectionMetaEvent(1, CollectionMetaEventType.sortChanged),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    pendingSort.complete();
    await tester.pumpAndSettle();
    expect(key.currentState!.galleryGroups!.groupType, GroupType.day);
    expect(key.currentState!.galleryGroups!.groupHeaderExtent, greaterThan(2));
    expect(key.currentState!.galleryGroups!.allFiles.first.title, "IMG201.jpg");

    order = FileSortOrder.filenameDescending;
    Bus.instance.fire(
      CollectionMetaEvent(1, CollectionMetaEventType.sortChanged),
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(key.currentState!.galleryGroups!.groupType, GroupType.none);
    expect(key.currentState!.galleryGroups!.allFiles.first.title, "IMG201.jpg");
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets(
    "pinching selection galleries changes density without changing selection",
    (tester) async {
      for (final mode in ["sheet", "single", "selected"]) {
        await localSettings.setPhotoGridSize(4);
        final galleryKey = GlobalKey<GalleryState>();
        final files = List.generate(
          12,
          (index) => EnteFile()
            ..generatedID = index + 1
            ..creationTime = DateTime(2026, 8, 19).microsecondsSinceEpoch
            ..fileType = FileType.image
            ..title = "photo-$index.jpg",
        );
        final selectedFiles = SelectedFiles();
        if (mode == "selected") selectedFiles.selectAll({files.first});
        var selectionChanges = 0;
        selectedFiles.addListener(() => selectionChanges++);
        final selectionBefore = selectedFiles.files.toSet();
        await _mountPinchGallery(
          tester,
          Gallery(
            key: galleryKey,
            asyncLoader: (start, end, {limit, asc}) async =>
                FileLoadResult(files, false),
            selectedFiles: selectedFiles,
            tagPrefix: "pinch_$mode",
            enableFileGrouping: false,
            inSelectionMode: mode == "sheet",
            limitSelectionToOne: mode == "single",
            showSelectAll: false,
          ),
        );
        selectionChanges = 0;

        final first = await tester.startGesture(
          const Offset(120, 150),
          pointer: 1,
        );
        final second = await tester.startGesture(
          const Offset(280, 150),
          pointer: 2,
        );
        await first.moveTo(const Offset(150, 150));
        await second.moveTo(const Offset(250, 150));
        await tester.pump();
        expect(
          find.byKey(const ValueKey("gallery-grid-zoom-overlay")),
          findsOneWidget,
          reason: mode,
        );
        expect(localSettings.getPhotoGridSize(), 4, reason: mode);
        await first.up();
        await second.up();
        await tester.pumpAndSettle();

        expect(localSettings.getPhotoGridSize(), 5, reason: mode);
        expect(galleryKey.currentState!.galleryGroups!.crossAxisCount, 5);
        expect(selectedFiles.files, unorderedEquals(selectionBefore));
        expect(selectionChanges, 0, reason: mode);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
        selectedFiles.dispose();
      }
    },
  );

  testWidgets("fixed-layout and non-scrollable galleries ignore pinches", (
    tester,
  ) async {
    for (final fixedLayout in [false, true]) {
      await localSettings.setPhotoGridSize(4);
      final galleryKey = GlobalKey<GalleryState>();
      await _mountPinchGallery(
        tester,
        Gallery(
          key: galleryKey,
          asyncLoader: (start, end, {limit, asc}) async =>
              FileLoadResult(List.generate(12, _justifiedTestFile), false),
          tagPrefix: "pinch_excluded",
          enableFileGrouping: false,
          disableScroll: !fixedLayout,
          layoutTypeOverride: fixedLayout ? GalleryLayoutType.grid : null,
        ),
      );
      final first = await tester.startGesture(
        const Offset(120, 150),
        pointer: 1,
      );
      final second = await tester.startGesture(
        const Offset(280, 150),
        pointer: 2,
      );
      await first.moveTo(const Offset(150, 150));
      await second.moveTo(const Offset(250, 150));
      await tester.pump();
      expect(
        find.byKey(const ValueKey("gallery-grid-zoom-overlay")),
        findsNothing,
      );
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(localSettings.getPhotoGridSize(), 4);
      expect(galleryKey.currentState!.galleryGroups!.crossAxisCount, 4);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    }
  });

  testWidgets("keeps the current gallery controller after an animated swap", (
    tester,
  ) async {
    final boundariesKey = GlobalKey<GalleryBoundariesProviderState>();
    late StateSetter replaceGallery;
    var generation = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: StringsLocalizations.supportedLocales,
        home: GalleryBoundariesProvider(
          key: boundariesKey,
          child: GalleryFilesState(
            child: StatefulBuilder(
              builder: (context, setState) {
                replaceGallery = setState;
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Gallery(
                    key: ValueKey(generation),
                    asyncLoader: (start, end, {limit, asc}) async =>
                        FileLoadResult([_dummyFile("handoff")], false),
                    tagPrefix: "handoff",
                    enableFileGrouping: false,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final controllers = boundariesKey.currentState!.scrollControllerNotifier;
    final previous = controllers.value;
    replaceGallery(() => generation++);
    await tester.pump();
    final current = controllers.value;
    expect(current, isNotNull);
    expect(current, isNot(same(previous)));
    await tester.pumpAndSettle();
    expect(controllers.value, same(current));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets(
    "retries late headers, refreshes pinned dates immediately and stops on disposal",
    (tester) async {
      final pinnedHeader = find.byWidgetPredicate(
        (widget) => widget is GroupHeaderWidget && widget.isPinnedHeader,
      );
      for (final disposeWhileLoading in [false, true]) {
        final load = Completer<FileLoadResult>();
        await tester.pumpWidget(
          MaterialApp(
            theme: lightThemeData,
            localizationsDelegates: StringsLocalizations.localizationsDelegates,
            supportedLocales: StringsLocalizations.supportedLocales,
            home: _galleryHost(
              Gallery(
                asyncLoader: (start, end, {limit, asc}) => load.future,
                tagPrefix: "late_header",
                groupType: GroupType.day,
                header: const SizedBox(height: 80),
                loadingWidget: const SizedBox.shrink(),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 750));
        if (!disposeWhileLoading) {
          load.complete(
            FileLoadResult(List.generate(100, _justifiedTestFile), false),
          );
          await tester.pumpAndSettle();
          final pinned = tester.widget<PinnedGroupHeader>(
            find.byType(PinnedGroupHeader),
          );
          expect(pinned.headerHeightNotifier.value, isNull);
          pinned.scrollController.jumpTo(160);
          await tester.pump();
          expect(pinnedHeader, findsNothing);
          await tester.pump(const Duration(milliseconds: 750));
          expect(pinned.headerHeightNotifier.value, 80);
          expect(pinnedHeader, findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    "both entry points preserve grouping and the remembered Grid count",
    (tester) async {
      var events = 0;
      final subscription = Bus.instance.on<GalleryLayoutChangedEvent>().listen(
        (_) => events++,
      );
      addTearDown(subscription.cancel);
      for (final quickMenu in [true, false]) {
        await localSettings.setGalleryLayoutType(GalleryLayoutType.grid);
        await localSettings.setPhotoGridSize(5);
        await localSettings.setGalleryGroupType(GroupType.month);
        events = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: lightThemeData,
            localizationsDelegates: StringsLocalizations.localizationsDelegates,
            supportedLocales: StringsLocalizations.supportedLocales,
            home: quickMenu
                ? const Scaffold(body: GalleryLayoutSettings())
                : const GallerySettingsScreen(
                    fromGalleryLayoutSettingsCTA: true,
                  ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text("Photos per row"), findsOneWidget);
        final cardTop = tester
            .getTopLeft(find.byKey(const ValueKey(GalleryLayoutType.grid)))
            .dy;
        final groupingTop = tester.getTopLeft(find.text("Group by")).dy;
        final sheetHeight = quickMenu
            ? tester.getSize(find.byType(GalleryLayoutSettings)).height
            : null;
        expect(find.text("Grid"), findsNothing);
        expect(find.text("Justified"), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey(GalleryLayoutType.justified)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        if (quickMenu) {
          expect(
            tester.getSize(find.byType(GalleryLayoutSettings)).height,
            sheetHeight,
          );
          expect(
            tester
                .getTopLeft(find.byKey(const ValueKey(GalleryLayoutType.grid)))
                .dy,
            cardTop,
          );
        }
        await tester.pumpAndSettle();
        expect(
          localSettings.getGalleryLayoutType(),
          GalleryLayoutType.justified,
        );
        expect(find.text("Photos per row").hitTestable(), findsNothing);
        if (quickMenu) {
          expect(
            tester.getSize(find.byType(GalleryLayoutSettings)).height,
            sheetHeight,
          );
          expect(
            tester
                .getTopLeft(find.byKey(const ValueKey(GalleryLayoutType.grid)))
                .dy,
            cardTop,
          );
          expect(
            tester.getTopLeft(find.text("Group by")).dy,
            lessThan(groupingTop),
          );
        }
        expect(localSettings.getPhotoGridSize(), 5);
        expect(localSettings.getGalleryGroupType(), GroupType.month);
        expect(events, 1);
        await tester.tap(find.byKey(const ValueKey(GalleryLayoutType.grid)));
        await tester.pumpAndSettle();
        expect(find.text("5"), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey("more-photos-per-row")));
        await tester.pumpAndSettle();
        expect(localSettings.getPhotoGridSize(), 6);
        expect(localSettings.getGalleryGroupType(), GroupType.month);
        expect(events, 3);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );

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
    await localSettings.setPhotoGridSize(3);
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
    final anchorFile = files[804];
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
    expect(newGeometry.rowExtent, isNot(oldGeometry.rowExtent));
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

      await localSettings.setPhotoGridSize(3);
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

Future<void> _mountPinchGallery(WidgetTester tester, Gallery gallery) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: lightThemeData,
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      supportedLocales: StringsLocalizations.supportedLocales,
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 400, height: 600, child: _galleryHost(gallery)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _GalleryFileSortApi extends Fake implements EntePhotosRustApi {
  Completer<void>? nextCall;

  @override
  Future<Uint32List> crateApiFileSortApiSortedFilenameIndices({
    required List<String> names,
    required Int64List fileIds,
    required String locale,
    required bool ascending,
  }) async {
    final pending = nextCall;
    nextCall = null;
    if (pending != null) await pending.future;
    return Uint32List.fromList(
      List.generate(names.length, (i) => ascending ? names.length - i - 1 : i),
    );
  }
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
