import "dart:async";

import "package:dio/dio.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/events/event.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/gallery_layout_changed_event.dart";
import "package:photos/models/file/dummy_file.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/file_load_result.dart";
import "package:photos/models/gallery/fixed_extent_grid_row.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/service_locator.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/ui/settings/gallery_settings_screen.dart";
import "package:photos/ui/viewer/gallery/component/group/group_header_widget.dart";
import "package:photos/ui/viewer/gallery/component/group/type.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/gallery_app_bar_config.dart";
import "package:photos/ui/viewer/gallery/gallery_grid_zoom.dart";
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

  testWidgets(
    "zero-size startup recovers date headers without remounting or reloading",
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size.zero;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await localSettings.setPhotoGridSize(4);
      final galleryKey = GlobalKey<GalleryState>();
      final files = List<EnteFile>.generate(
        8,
        (index) => _justifiedTestFile(index)
          ..creationTime = DateTime(
            2026,
            8,
            19 - index ~/ 4,
          ).microsecondsSinceEpoch,
      );
      final load = Completer<FileLoadResult>();
      var loads = 0;
      await tester.pumpWidget(
        _viewSizedGalleryHost(
          Gallery(
            key: galleryKey,
            tagPrefix: "zero_size_header",
            groupType: GroupType.day,
            initialFiles: [files.first],
            loadingWidget: const SizedBox.shrink(),
            asyncLoader: (start, end, {limit, asc}) {
              loads++;
              return load.future;
            },
          ),
        ),
      );
      final originalState = galleryKey.currentState!;
      load.complete(FileLoadResult(files, false));
      await tester.pumpAndSettle();
      expect(originalState.groupHeaderExtent, isNull);
      expect(originalState.galleryGroups, isNull);
      expect(loads, 1);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(400, 600);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(galleryKey.currentState, same(originalState));
      final groups = originalState.galleryGroups!;
      expect(groups.allFiles, orderedEquals(files));
      expect(groups.groupIDs, hasLength(2));
      expect(groups.groupHeaderExtent, greaterThan(0));
      expect(loads, 1);
      final header = find.byWidgetPredicate(
        (widget) =>
            widget is GroupHeaderWidget &&
            !widget.isPinnedHeader &&
            widget.filesInGroup.contains(files.first),
      );
      expect(header, findsOneWidget);
      final headerRect = tester.getRect(header);
      final firstRowRect = tester.getRect(
        find.byType(FixedExtentGridRow).first,
      );
      expect(headerRect.height, closeTo(groups.groupHeaderExtent, 0.001));
      expect(firstRowRect.top, greaterThanOrEqualTo(headerRect.bottom - 0.001));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    },
  );

  testWidgets(
    "a layout change with a zero-size overlay retains a valid header cache",
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 600);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      await localSettings.setPhotoGridSize(4);
      final galleryKey = GlobalKey<GalleryState>();
      final files = List<EnteFile>.generate(4, _justifiedTestFile);
      var loads = 0;
      await tester.pumpWidget(
        _viewSizedGalleryHost(
          Gallery(
            key: galleryKey,
            tagPrefix: "retain_header_cache",
            groupType: GroupType.day,
            asyncLoader: (start, end, {limit, asc}) async {
              loads++;
              return FileLoadResult(files, false);
            },
          ),
          keepGallerySize: true,
        ),
      );
      await tester.pumpAndSettle();
      final originalState = galleryKey.currentState!;
      final headerExtent = originalState.groupHeaderExtent!;
      expect(headerExtent, greaterThan(0));

      tester.view.physicalSize = Size.zero;
      await tester.pump();
      final overlay =
          Overlay.of(galleryKey.currentContext!).context.findRenderObject()!
              as RenderBox;
      expect(overlay.size, Size.zero);
      Bus.instance.fire(GalleryLayoutChangedEvent());
      await tester.pumpAndSettle();
      expect(originalState.groupHeaderExtent, headerExtent);
      expect(originalState.galleryGroups!.groupHeaderExtent, headerExtent);
      expect(tester.takeException(), isNull);

      tester.view.physicalSize = const Size(400, 600);
      await tester.pumpAndSettle();
      expect(galleryKey.currentState, same(originalState));
      expect(originalState.groupHeaderExtent, headerExtent);
      expect(originalState.galleryGroups!.allFiles, orderedEquals(files));
      expect(loads, 1);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    },
  );

  testWidgets(
    "zero-width startup keeps loading and lays out all files on recovery",
    (tester) async {
      for (final layout in [
        GalleryLayoutType.grid,
        GalleryLayoutType.justified,
      ]) {
        await localSettings.setGalleryLayoutType(layout);
        final width = ValueNotifier<double>(0);
        final galleryKey = GlobalKey<GalleryState>();
        final files = List<EnteFile>.generate(200, _justifiedTestFile);
        final firstPage = Completer<FileLoadResult>();
        final loadLimits = <int?>[];
        await tester.pumpWidget(
          _resizableGalleryHost(
            width,
            Gallery(
              key: galleryKey,
              tagPrefix: "zero_width_startup",
              groupType: GroupType.month,
              loadingWidget: const SizedBox.shrink(),
              asyncLoader: (start, end, {limit, asc}) {
                loadLimits.add(limit);
                return loadLimits.length == 1
                    ? firstPage.future
                    : Future.value(FileLoadResult(files, false));
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        firstPage.complete(FileLoadResult(files.take(100).toList(), true));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        expect(loadLimits, [100, null]);
        expect(galleryKey.currentState!.galleryGroups, isNull);
        expect(find.byType(GalleryGridZoom), findsNothing);

        width.value = 400;
        await tester.pump();
        await tester.pumpAndSettle();
        final groups = galleryKey.currentState!.galleryGroups!;
        expect(groups.widthAvailable, 400);
        expect(groups.allFiles, orderedEquals(files));
        expect(groups.getGeometryOfFile(files.last), isNotNull);
        expect(loadLimits, [100, null]);
        expect(find.byType(GalleryGridZoom), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
        width.dispose();
      }
    },
  );

  testWidgets("zero-width refresh keeps the existing gallery mounted", (
    tester,
  ) async {
    await localSettings.setGalleryLayoutType(GalleryLayoutType.justified);
    final width = ValueNotifier<double>(400);
    final galleryKey = GlobalKey<GalleryState>();
    final reload = StreamController<Event>.broadcast();
    var files = List<EnteFile>.generate(12, _justifiedTestFile);
    var loads = 0;
    await tester.pumpWidget(
      _resizableGalleryHost(
        width,
        Gallery(
          key: galleryKey,
          tagPrefix: "zero_width_refresh",
          reloadDebounceTime: Duration.zero,
          enableFileGrouping: false,
          forceReloadEvents: [reload.stream],
          asyncLoader: (start, end, {limit, asc}) async {
            loads++;
            return FileLoadResult(files, false);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final originalGroups = galleryKey.currentState!.galleryGroups!;
    expect(originalGroups.allFiles, hasLength(12));
    final scrollableFinder = find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    );
    final scrollable = tester.state<ScrollableState>(scrollableFinder);
    scrollable.position.jumpTo(150);
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(scrollableFinder).position.pixels,
      150,
    );

    width.value = 0;
    await tester.pump();
    files = List<EnteFile>.generate(24, _justifiedTestFile);
    reload.add(Event());
    await tester.pumpAndSettle();
    expect(loads, 2);
    expect(galleryKey.currentState!.galleryGroups, same(originalGroups));
    expect(tester.state<ScrollableState>(scrollableFinder), same(scrollable));
    expect(tester.takeException(), isNull);

    width.value = 400;
    await tester.pumpAndSettle();
    reload.add(Event());
    await tester.pumpAndSettle();
    final groups = galleryKey.currentState!.galleryGroups!;
    expect(groups.widthAvailable, originalGroups.widthAvailable);
    expect(groups.allFiles, orderedEquals(files));
    expect(groups.getGeometryOfFile(files.last), isNotNull);
    expect(loads, 3);
    expect(
      tester.state<ScrollableState>(scrollableFinder).position.pixels,
      150,
    );
    expect(tester.state<ScrollableState>(scrollableFinder), same(scrollable));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await reload.close();
    width.dispose();
  });

  testWidgets("zero-width refresh retains the displayed empty state", (
    tester,
  ) async {
    final width = ValueNotifier<double>(400);
    final galleryKey = GlobalKey<GalleryState>();
    final reload = StreamController<Event>.broadcast();
    var files = <EnteFile>[];
    const emptyStateKey = ValueKey("zero_width_empty_state");
    await tester.pumpWidget(
      _resizableGalleryHost(
        width,
        Gallery(
          key: galleryKey,
          tagPrefix: "zero_width_empty_refresh",
          groupType: GroupType.month,
          emptyState: const SizedBox(key: emptyStateKey),
          forceReloadEvents: [reload.stream],
          asyncLoader: (start, end, {limit, asc}) async =>
              FileLoadResult(files, false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final originalGroups = galleryKey.currentState!.galleryGroups!;
    expect(originalGroups.allFiles, isEmpty);
    expect(find.byKey(emptyStateKey), findsOneWidget);

    width.value = 0;
    await tester.pump();
    files = List<EnteFile>.generate(12, _justifiedTestFile);
    reload.add(Event());
    await tester.pumpAndSettle();
    width.value = 400;
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    expect(galleryKey.currentState!.galleryGroups, same(originalGroups));
    expect(find.byKey(emptyStateKey), findsOneWidget);
    expect(find.byType(PinnedGroupHeader), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await reload.close();
    width.dispose();
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
    "layout changes rebuild every visible gallery without loading files",
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

  testWidgets(
    "covered galleries defer grid rebuilds while file loading continues",
    (tester) async {
      await localSettings.setPhotoGridSize(4);
      final navigation = GlobalKey<NavigatorState>();
      final coveredKey = GlobalKey<GalleryState>();
      final visibleKey = GlobalKey<GalleryState>();
      final files = List<EnteFile>.generate(1000, _justifiedTestFile);
      var loadedFiles = files;
      final reloads = StreamController<FilesUpdatedEvent>.broadcast();
      addTearDown(reloads.close);
      var coveredLoads = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigation,
          theme: lightThemeData,
          home: _galleryHost(
            Gallery(
              key: coveredKey,
              asyncLoader: (start, end, {limit, asc}) async {
                coveredLoads++;
                return FileLoadResult(loadedFiles, false);
              },
              reloadEvent: reloads.stream,
              tagPrefix: "covered_",
              enableFileGrouping: false,
              showSelectAll: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final oldGroups = coveredKey.currentState!.galleryGroups!;
      final anchor = files[804];
      final oldGeometry = oldGroups.getGeometryOfFile(anchor)!;
      const progress = 0.5;
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;
      position.jumpTo(oldGeometry.rowOffset + oldGeometry.rowExtent * progress);
      await tester.pump();
      final oldOffset = position.pixels;
      unawaited(
        navigation.currentState!.push<void>(
          MaterialPageRoute(
            builder: (_) => _galleryHost(
              Gallery(
                key: visibleKey,
                asyncLoader: (start, end, {limit, asc}) async =>
                    FileLoadResult(files, false),
                tagPrefix: "visible_",
                enableFileGrouping: false,
                showSelectAll: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final columns in [6, 3]) {
        await localSettings.setPhotoGridSize(columns);
        Bus.instance.fire(GalleryLayoutChangedEvent());
        await tester.pumpAndSettle();
        expect(visibleKey.currentState!.galleryGroups!.crossAxisCount, columns);
        expect(coveredKey.currentState!.galleryGroups, same(oldGroups));
        expect(position.pixels, oldOffset);
        expect(coveredLoads, 1);
      }

      final addedFile = _justifiedTestFile(1000);
      loadedFiles = [...files, addedFile];
      reloads.add(FilesUpdatedEvent([addedFile]));
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(coveredLoads, 2);
      expect(coveredKey.currentState!.galleryGroups, same(oldGroups));
      expect(position.pixels, oldOffset);

      navigation.currentState!.pop();
      await tester.pumpAndSettle();
      final newGroups = coveredKey.currentState!.galleryGroups!;
      expect(newGroups.crossAxisCount, 3);
      expect(newGroups.allFiles.last, same(addedFile));
      final newGeometry = newGroups.getGeometryOfFile(anchor)!;
      expect(
        position.pixels,
        closeTo(
          newGeometry.rowOffset + newGeometry.rowExtent * progress,
          0.001,
        ),
      );
      expect(coveredLoads, 2);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
    },
  );

  testWidgets("the layout sheet previews only its own gallery", (tester) async {
    await localSettings.setPhotoGridSize(4);
    await localSettings.setGalleryGroupType(GroupType.day);
    final navigation = GlobalKey<NavigatorState>();
    final coveredKey = GlobalKey<GalleryState>();
    final previewKey = GlobalKey<GalleryState>();
    final files = List<EnteFile>.generate(100, _justifiedTestFile);
    var latestFiles = files;
    final reloads = StreamController<FilesUpdatedEvent>.broadcast();
    addTearDown(reloads.close);
    final loads = [0, 0];
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigation,
        theme: lightThemeData.copyWith(platform: TargetPlatform.iOS),
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: StringsLocalizations.supportedLocales,
        home: _galleryHost(
          Gallery(
            key: coveredKey,
            asyncLoader: (start, end, {limit, asc}) async {
              loads[0]++;
              return FileLoadResult(files, false);
            },
            tagPrefix: "behind_preview_",
            enableFileGrouping: false,
            showSelectAll: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final coveredGroups = coveredKey.currentState!.galleryGroups;
    unawaited(
      navigation.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => _galleryHost(
            Gallery(
              key: previewKey,
              asyncLoader: (start, end, {limit, asc}) async {
                loads[1]++;
                return FileLoadResult(latestFiles, false);
              },
              reloadEvent: reloads.stream,
              tagPrefix: "preview_",
              showGallerySettingsCTA: true,
              showSelectAll: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert_outlined).hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.byType(GalleryLayoutSettings), findsOneWidget);

    final addedFile = _justifiedTestFile(100);
    latestFiles = [...files, addedFile];
    reloads.add(FilesUpdatedEvent([addedFile]));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byKey(const ValueKey("more-photos-per-row")));
    await tester.pumpAndSettle();
    expect(previewKey.currentState!.galleryGroups!.crossAxisCount, 5);
    expect(previewKey.currentState!.galleryGroups!.allFiles.last, addedFile);
    expect(coveredKey.currentState!.galleryGroups, same(coveredGroups));
    expect(loads, [1, 2]);

    await tester.tap(find.text("Group by"));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Month"));
    await tester.pumpAndSettle();
    expect(find.byType(GalleryLayoutSettings), findsOneWidget);
    expect(previewKey.currentState!.galleryGroups!.groupType, GroupType.month);
    await tester.tap(find.byKey(const ValueKey(GalleryLayoutType.justified)));
    await tester.pumpAndSettle();
    final previewGroups = previewKey.currentState!.galleryGroups!;
    expect(previewGroups.layoutType, GalleryLayoutType.justified);
    expect(coveredKey.currentState!.galleryGroups, same(coveredGroups));
    expect(loads, [1, 2]);

    navigation.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.byType(GalleryLayoutSettings), findsNothing);
    expect(previewKey.currentState!.galleryGroups!.allFiles.last, addedFile);
    expect(loads, [1, 2]);
    expect(coveredKey.currentState!.galleryGroups, same(coveredGroups));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
  });

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

Widget _viewSizedGalleryHost(Gallery gallery, {bool keepGallerySize = false}) {
  return MaterialApp(
    theme: lightThemeData,
    localizationsDelegates: StringsLocalizations.localizationsDelegates,
    supportedLocales: StringsLocalizations.supportedLocales,
    home: Builder(
      builder: (context) {
        final child = _galleryHost(gallery);
        if (!keepGallerySize) return child;
        // Keep gallery layout usable while the measurement overlay becomes zero.
        return OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 400,
          maxWidth: 400,
          minHeight: 600,
          maxHeight: 600,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(size: const Size(400, 600)),
            child: child,
          ),
        );
      },
    ),
  );
}

Widget _resizableGalleryHost(ValueNotifier<double> width, Gallery gallery) {
  return MaterialApp(
    theme: lightThemeData,
    localizationsDelegates: StringsLocalizations.localizationsDelegates,
    supportedLocales: StringsLocalizations.supportedLocales,
    home: ValueListenableBuilder<double>(
      valueListenable: width,
      child: _galleryHost(gallery),
      builder: (context, value, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(size: Size(value, 600)),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: value, height: 600, child: child),
        ),
      ),
    ),
  );
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
