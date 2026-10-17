import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:typed_data";
import "dart:ui" as ui;

import "package:dio/dio.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/loading_widget.dart";
import "package:figma_squircle/figma_squircle.dart";
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter/services.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:flutter_test/flutter_test.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:photos/core/cache/thumbnail_in_memory_cache.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/events/collection_meta_event.dart";
import "package:photos/events/collection_updated_event.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/gateways/entity/models/type.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/collection/collection_items.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/gallery_type.dart";
import "package:photos/models/ignored_file.dart";
import "package:photos/models/local_entity_data.dart";
import "package:photos/models/metadata/collection_magic.dart";
import "package:photos/models/metadata/common_keys.dart";
import "package:photos/models/ml/face/face.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/models/search/hierarchical/camera_filter.dart";
import "package:photos/models/search/hierarchical/face_filter.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/module/download/thumbnail.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/app_navigation_service.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/entity_service.dart";
import "package:photos/services/favorites_service.dart";
import "package:photos/services/ignored_files_service.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/src/rust/frb_generated.dart";
import "package:photos/ui/collections/album/row_item.dart";
import "package:photos/ui/collections/collection_list_page.dart";
import "package:photos/ui/components/bottom_action_bar/action_bar_widget.dart";
import "package:photos/ui/components/bottom_action_bar/selection_action_sheet.dart";
import "package:photos/ui/viewer/actions/album_selection_overlay_bar.dart";
import "package:photos/ui/viewer/actions/file_selection_overlay_bar.dart";
import "package:photos/ui/viewer/gallery/collection_page.dart";
import "package:photos/ui/viewer/gallery/component/album_cover_app_bar.dart";
import "package:photos/ui/viewer/gallery/component/gallery_file_widget.dart";
import "package:photos/ui/viewer/gallery/component/group/group_header_widget.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/gallery_app_bar_widget.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:photos/ui/viewer/gallery/state/inherited_search_filter_data.dart";
import "package:photos/ui/viewer/gallery/state/search_filter_data_provider.dart";
import "package:photos/ui/viewer/hierarchicial_search/app_bar_filter_chips.dart";
import "package:photos/ui/viewer/people/person_face_widget.dart";
import "package:photos/utils/face/face_thumbnail_cache.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late PathProviderPlatform previousPathProvider;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp("collection_page_cover_");
    previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({"remote_flags": "{}"});
    final preferences = await SharedPreferences.getInstance();
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response(requestOptions: options, data: <String, dynamic>{}),
          ),
        ),
      );
    ServiceLocator.instance.init(
      preferences,
      dio,
      Dio(),
      Dio(),
      PackageInfo(
        appName: "Photos",
        packageName: "photos",
        version: "1.0.0",
        buildNumber: "1",
      ),
    );
    try {
      await Configuration.instance.init(preferences);
    } catch (_) {}
    await Configuration.instance.setUserID(1);
    await Configuration.instance.setKey(base64Encode(List.filled(32, 0)));
    await Configuration.instance.setToken("test-token");
    await CollectionsService.instance.init(preferences);
    await FavoritesService.instance.initFav();
    expect(flagService.internalUser, isTrue);
  });

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel("dev.fluttercommunity.plus/connectivity_status"),
          (_) async => null,
        );
    await FilesDB.instance.clearTable();
    await IgnoredFilesService.instance.reset();
    Bus.instance.fire(CollectionUpdatedEvent(1, [], "test_reset"));
    await Future<void>.delayed(Duration.zero);
  });

  tearDownAll(() async {
    PathProviderPlatform.instance = previousPathProvider;
    await tempDir.delete(recursive: true);
  });

  testWidgets("keeps interactive back when the album route fades", (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData.copyWith(platform: TargetPlatform.iOS),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => routeToPage(
              context,
              const Scaffold(body: Center(child: Text("Album route"))),
              useFadeTransition: true,
            ),
            child: const Text("Open album"),
          ),
        ),
      ),
    );
    await tester.tap(find.text("Open album"));
    await tester.pumpAndSettle();
    await tester.timedDragFrom(
      const Offset(1, 300),
      const Offset(80, 0),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(find.text("Album route"), findsOneWidget);
    await tester.timedDragFrom(
      const Offset(1, 300),
      const Offset(700, 0),
      const Duration(seconds: 1),
    );
    await tester.pumpAndSettle();
    expect(find.text("Album route"), findsNothing);
    expect(find.text("Open album"), findsOneWidget);
  });

  for (final isOwner in [true, false]) {
    testWidgets(
      "hiding ${isOwner ? 'an owned' : 'a received'} album keeps it usable until closed",
      (tester) async {
        final collection = _collection(ownerID: isOwner ? 1 : 2);
        final file = _file(1);
        await tester.runAsync(() => FilesDB.instance.insertMultiple([file]));
        await _pumpAlbum(tester, collection);
        await _expectCover(tester, file, count: 1);

        if (isOwner) {
          collection.mMdVersion = 1;
          collection.magicMetadata = CollectionMagicMetadata(
            visibility: hiddenVisibility,
          );
        } else {
          collection.sharedMmdVersion = 1;
          collection.sharedMagicMetadata = ShareeMagicMetadata(
            visibility: hiddenVisibility,
          );
        }
        Bus.instance.fire(
          CollectionUpdatedEvent(1, [], "test_hide", type: EventType.hide),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip("More"));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheetComponent), findsOneWidget);

        await _disposeAlbum(tester);
        await _pumpAlbum(tester, collection);
        expect(find.byType(Gallery), findsNothing);
        await _disposeAlbum(tester);
      },
    );
  }

  testWidgets("paints the pinned date flush with the album app bar", (
    tester,
  ) async {
    const pixelRatio = 2.8125;
    tester.view.devicePixelRatio = pixelRatio;
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.padding = const FakeViewPadding(top: 95, bottom: 135);
    addTearDown(tester.view.reset);
    final files = List.generate(100, (index) => _file(index + 1));
    await tester.runAsync(() => FilesDB.instance.insertMultiple(files));
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          theme: darkThemeData,
          localizationsDelegates: StringsLocalizations.localizationsDelegates,
          supportedLocales: StringsLocalizations.supportedLocales,
          home: CollectionPage(
            CollectionWithThumbnail(_collection(), files.last),
          ),
        ),
      ),
    );
    await _expectCover(tester, files.last, count: files.length);
    final pinned = tester.widget<PinnedGroupHeader>(
      find.byType(PinnedGroupHeader),
    );
    pinned.scrollController.jumpTo(pinned.scrollOffsetBase + 80);
    await tester.pumpAndSettle();
    final header = find.byWidgetPredicate(
      (widget) => widget is GroupHeaderWidget && widget.isPinnedHeader,
    );
    expect(header, findsOneWidget);
    final top = tester.getTopLeft(header).dy * pixelRatio;
    final background = GalleryAppBarWidget.backgroundColor(
      tester.element(header),
    );
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = (await tester.runAsync(
      () => boundary.toImage(pixelRatio: pixelRatio),
    ))!;
    addTearDown(image.dispose);
    final pixels = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    ))!;
    final backgroundArgb = background.toARGB32();
    for (var y = top.floor() - 1; y <= top.ceil(); y++) {
      final offset = (y * image.width + 4) * 4;
      expect(
        pixels.buffer.asUint8List(offset, 3),
        [
          (backgroundArgb >> 16) & 0xff,
          (backgroundArgb >> 8) & 0xff,
          backgroundArgb & 0xff,
        ],
        reason:
            "The album/date boundary must hide the photos at physical row $y",
      );
    }
    await _disposeAlbum(tester);
  });

  for (final fileCount in [1, 30]) {
    testWidgets("anchors $fileCount photos through album cover collapse", (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(402, 874);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final previousLayout = localSettings.getGalleryLayoutType();
      final previousGridSize = localSettings.getPhotoGridSize();
      addTearDown(() async {
        await localSettings.setGalleryLayoutType(previousLayout);
        await localSettings.setPhotoGridSize(previousGridSize);
      });
      await localSettings.setGalleryLayoutType(GalleryLayoutType.justified);
      await localSettings.setPhotoGridSize(5);
      final collection = _collection();
      final files = List.generate(
        fileCount,
        (index) => _file(index + 1)..pubMmdEncodedJson = '{"w":400,"h":600}',
      );
      await tester.runAsync(() async {
        await FilesDB.instance.insertMultiple(files);
        await CollectionsService.instance.getCover(collection);
      });
      await _pumpAlbum(tester, collection);
      await _expectCover(tester, files.last, count: fileCount);
      final boundaries = tester.state<GalleryBoundariesProviderState>(
        find.byType(GalleryBoundariesProvider),
      );
      final position = boundaries.scrollControllerNotifier.value!.position;
      final header = tester.widget<AlbumCoverAppBar>(
        find.byType(AlbumCoverAppBar),
      );
      final geometry = AlbumCoverAppBar.resolveGeometry(
        tester.element(find.byType(AlbumCoverAppBar)),
        collapsedHeight: header.collapsedHeight,
        bottomHeight: header.bottom?.preferredSize.height ?? 0,
      );
      if (fileCount == 1) {
        expect(
          position.maxScrollExtent,
          closeTo(geometry.collapseExtent, 0.01),
        );
      }
      for (final fraction in [0.0, 0.5, 1.0]) {
        final offset = geometry.collapseExtent * fraction;
        position.jumpTo(offset);
        await tester.pumpAndSettle();
        final tileRect = tester.getRect(find.byType(GalleryFileWidget).first);
        final viewport = tester.getRect(find.byType(CustomScrollView));
        final focalPoint = tileRect.intersect(viewport).center;
        final first = await tester.startGesture(
          focalPoint - const Offset(30, 0),
          pointer: 1,
        );
        final second = await tester.startGesture(
          focalPoint + const Offset(30, 0),
          pointer: 2,
        );
        await tester.pump();
        final overlayTile = find.byKey(
          const ValueKey(("gallery-grid-zoom-tile", 0)),
        );
        expect(overlayTile, findsOneWidget);
        expect(
          tester.getRect(overlayTile),
          rectMoreOrLessEquals(tileRect, epsilon: 0.01),
        );
        await second.up();
        await first.up();
        await tester.pumpAndSettle();
        expect(position.pixels, closeTo(offset, 0.01));
      }
      if (fileCount == 1) {
        position.jumpTo(0);
        await tester.pump();
        await tester.drag(
          find.byType(CustomScrollView),
          Offset(0, -geometry.collapseExtent * 1.5),
        );
        await tester.pumpAndSettle();
        expect(position.pixels, closeTo(geometry.collapseExtent, 0.01));
      }
      expect(tester.takeException(), isNull);
      await _disposeAlbum(tester);
    });
  }

  testWidgets("uses a pending local photo and excludes ignored photos", (
    tester,
  ) async {
    final collection = _collection();
    final files = List.generate(
      101,
      (index) => _file(index + 1, uploaded: false),
    );
    final cover = files[99];
    final ignored = files.last;
    await tester.runAsync(() async {
      await FilesDB.instance.insertMultiple(files);
      await IgnoredFilesService.instance.cacheAndInsert([
        IgnoredFile(
          ignored.localID,
          ignored.title,
          ignored.deviceFolder,
          "ignored",
        ),
      ]);
    });

    await _pumpAlbum(tester, collection);
    await _expectCover(tester, cover, count: 100);
    expect(find.text("1 JAN – 10 APR 2026"), findsOneWidget);
    await _disposeAlbum(tester);
  });

  testWidgets(
    "refreshes sorted covers and preserves an explicitly selected cover",
    (tester) async {
      final collection = _collection();
      final oldest = _file(1);
      final newest = _file(3);
      await tester.runAsync(() async {
        await FilesDB.instance.insertMultiple([oldest, newest]);
        expect(await CollectionsService.instance.getCover(collection), newest);
      });
      await _pumpAlbum(tester, collection);
      await _expectCover(tester, newest, count: 2);
      final selectedFiles = tester
          .widget<GalleryAppBarWidget>(find.byType(GalleryAppBarWidget))
          .selectedFiles;
      expect(find.byType(AlbumCoverActionButton), findsNWidgets(2));
      expect(find.byTooltip("Sort"), findsNothing);
      await tester.tap(find.byTooltip("More"));
      await tester.pumpAndSettle();
      expect(find.text("Newest first"), findsOneWidget);
      await tester.tap(find.text("Sort"));
      await tester.pumpAndSettle();
      expect(find.text("Sort photos"), findsOneWidget);
      await tester.tap(find.text("Newest first"));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheetComponent), findsNothing);
      selectedFiles.toggleSelection(newest);
      await tester.pumpAndSettle();
      expect(find.byType(AlbumCoverActionButton), findsNothing);
      expect(find.byTooltip("Sort"), findsNothing);
      final boundaries = tester.state<GalleryBoundariesProviderState>(
        find.byType(GalleryBoundariesProvider),
      );
      final gallery = tester.state<GalleryState>(find.byType(Gallery));
      final padding = gallery.scrollbarBottomPaddingNotifier;
      final minHeight = boundaries.selectionSheetMinHeightNotifier.value!;
      expect(padding.value, minHeight);
      final position = boundaries.scrollControllerNotifier.value!.position;
      final scrollExtent = position.maxScrollExtent;
      final sheetToggle = find.descendant(
        of: find.byType(DraggableScrollableSheet),
        matching: find.bySemanticsLabel("More"),
      );
      var paddingUpdates = 0;
      void trackPadding() => paddingUpdates++;
      padding.addListener(trackPadding);
      await tester.tap(sheetToggle);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      final expandedBoundary = boundaries.bottomBoundaryNotifier.value!;
      expect(padding.value, minHeight);
      expect(position.maxScrollExtent, scrollExtent);
      await tester.tap(sheetToggle);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        boundaries.bottomBoundaryNotifier.value!,
        greaterThan(expandedBoundary),
      );
      expect(paddingUpdates, 0);
      expect(padding.value, minHeight);
      expect(position.maxScrollExtent, scrollExtent);
      padding.removeListener(trackPadding);
      await tester.tap(find.byType(SelectAllButton));
      await tester.pumpAndSettle();
      expect(selectedFiles.files, containsAll([oldest, newest]));
      await tester.tap(find.byType(ActionBarWidget));
      await tester.pumpAndSettle();
      expect(selectedFiles.files, isEmpty);
      expect(
        padding.value,
        MediaQuery.paddingOf(tester.element(find.byType(Gallery))).bottom,
      );
      expect(find.byType(AlbumCoverActionButton), findsNWidgets(2));
      expect(find.byTooltip("Sort"), findsNothing);

      collection.pubMagicMetadata = CollectionPubMagicMetadata(asc: true);
      Bus.instance.fire(
        CollectionMetaEvent(collection.id, CollectionMetaEventType.sortChanged),
      );
      await _expectCover(tester, oldest, count: 2);
      expect(find.text("1–3 JAN 2026"), findsOneWidget);
      await tester.tap(find.byTooltip("More"));
      await tester.pumpAndSettle();
      expect(find.text("Oldest first"), findsOneWidget);
      Navigator.of(tester.element(find.byType(CollectionPage))).pop();
      await tester.pumpAndSettle();

      final middle = _file(2);
      await tester.runAsync(() => FilesDB.instance.insertMultiple([middle]));
      Bus.instance.fire(
        CollectionUpdatedEvent(collection.id, [middle], "added"),
      );
      await _expectCover(tester, oldest, count: 3);

      collection.pubMagicMetadata = CollectionPubMagicMetadata(
        asc: true,
        coverID: 3,
      );
      Bus.instance.fire(
        CollectionUpdatedEvent(collection.id, [], "cover_change"),
      );
      await _expectCover(tester, newest);

      collection.pubMagicMetadata = CollectionPubMagicMetadata(asc: true);
      Bus.instance.fire(
        CollectionUpdatedEvent(collection.id, [], "cover_change"),
      );
      await _expectCover(tester, oldest);

      await tester.runAsync(
        () => FilesDB.instance.deleteCollection(collection.id),
      );
      Bus.instance.fire(CollectionUpdatedEvent(collection.id, [], "removed"));
      await _expectCover(tester, null);
      await _disposeAlbum(tester);
    },
  );

  testWidgets(
    "reuses capture dates across selection and refreshes date edits",
    (tester) async {
      final files = [_CountingFile(_file(1)), _CountingFile(_file(3))];
      final selectedFiles = SelectedFiles();
      final cover = _file(99);
      late StateSetter refresh;
      final galleryFiles = GalleryFilesState(
        child: StatefulBuilder(
          builder: (context, setState) {
            refresh = setState;
            final appBar = GalleryAppBarWidget.sliverConfig(
              GalleryType.ownedCollection,
              "Album",
              selectedFiles,
              collection: _collection(),
              cover: cover,
            );
            return Scaffold(
              body: CustomScrollView(slivers: [appBar.buildSliver(context)]),
            );
          },
        ),
      )..setGalleryFiles = files;
      await tester.pumpWidget(
        MaterialApp(
          theme: lightThemeData,
          localizationsDelegates: StringsLocalizations.localizationsDelegates,
          supportedLocales: StringsLocalizations.supportedLocales,
          navigatorObservers: [AppNavigationService.instance.routeObserver],
          home: galleryFiles,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text("1–3 JAN 2026"), findsOneWidget);
      final reads = files.map((file) => file.creationTimeReads).toList();
      for (final file in [files.first, files.last, files.first, files.last]) {
        selectedFiles.toggleSelection(file);
        await tester.pumpAndSettle();
        expect(files.map((file) => file.creationTimeReads), reads);
      }
      files.setAll(0, files.reversed.toList());
      files.last.creationTime = DateTime(2026, 1, 5).microsecondsSinceEpoch;
      galleryFiles.setGalleryFiles = files;
      refresh(() {});
      await tester.pumpAndSettle();
      expect(find.text("3–5 JAN 2026"), findsOneWidget);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator
          .push(MaterialPageRoute<void>(builder: (_) => const Scaffold()))
          .ignore();
      await tester.pumpAndSettle();
      files.last.creationTime = DateTime(2026, 1, 7).microsecondsSinceEpoch;
      navigator.pop();
      await tester.pumpAndSettle();
      expect(find.text("3–7 JAN 2026"), findsOneWidget);
      await _disposeAlbum(tester);
      selectedFiles.dispose();
    },
  );

  testWidgets(
    "keeps custom-bottom header geometry and menu actions consistent",
    (tester) async {
      final selectedFiles = SelectedFiles();
      final collection = _collection()
        ..pubMagicMetadata = CollectionPubMagicMetadata(
          description: "Description",
        );
      final appBar = GalleryAppBarWidget.sliverConfig(
        GalleryType.ownedCollection,
        "Album",
        selectedFiles,
        collection: collection,
        cover: _file(1),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(40),
          child: SizedBox(height: 40, child: Text("Custom bottom")),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: lightThemeData,
          localizationsDelegates: StringsLocalizations.localizationsDelegates,
          supportedLocales: StringsLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) =>
                  CustomScrollView(slivers: [appBar.buildSliver(context)]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SliverAppBarComponent), findsOneWidget);
      expect(find.text("Custom bottom"), findsOneWidget);
      final geometry = appBar.resolveGeometry(
        tester.element(find.byType(GalleryAppBarWidget)),
      );
      final header = tester.widget<SliverPersistentHeader>(
        find.byType(SliverPersistentHeader),
      );
      expect(geometry.minExtent, header.delegate.minExtent);
      expect(geometry.maxExtent, header.delegate.maxExtent);
      final menu = tester.widget<EntePopupMenuButton<AlbumPopupAction>>(
        find.byType(EntePopupMenuButton<AlbumPopupAction>),
      );
      final options = await menu.optionsBuilder();
      expect(
        options.map((option) => option.value),
        containsAll([
          AlbumPopupAction.map,
          AlbumPopupAction.sort,
          AlbumPopupAction.albumSlideshow,
        ]),
      );
      final sortSelection = Future.sync(
        () => menu.onSelected(AlbumPopupAction.sort),
      );
      await tester.pumpAndSettle();
      expect(find.text("Sort photos"), findsOneWidget);
      await tester.tap(find.text("Newest first"));
      await tester.pumpAndSettle();
      await sortSelection;
      await _disposeAlbum(tester);
      selectedFiles.dispose();
    },
  );

  testWidgets("album selection controls align and fill the bottom safe area", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: StringsLocalizations.supportedLocales,
        home: CollectionListPage([
          _collection(),
        ], sectionType: UISectionType.archivedCollections),
      ),
    );
    await tester.pumpAndSettle();
    final selected = tester
        .widget<AlbumSelectionOverlayBar>(find.byType(AlbumSelectionOverlayBar))
        .selectedAlbums;
    selected.select({_collection()});
    await tester.pumpAndSettle();
    final material = find.descendant(
      of: find.byType(SelectionActionSheet),
      matching: find.byType(Material),
    );
    expect(tester.getBottomRight(material).dy, 812);
    expect(
      tester.getTopLeft(find.byType(SelectAllAlbumsButton)).dx,
      tester.getTopLeft(material).dx + Spacing.sm,
    );
    await tester.tap(find.bySemanticsLabel(RegExp("Cancel,")));
    await tester.pumpAndSettle();
    expect(selected.albums, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets("anchors the selection sheet during interrupted resizing", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final file = _file(1);
    await tester.runAsync(() => FilesDB.instance.insertMultiple([file]));
    await _pumpAlbum(tester, _collection());
    await _expectCover(tester, file);
    final selectedFiles = tester
        .widget<FileSelectionOverlayBar>(find.byType(FileSelectionOverlayBar))
        .selectedFiles;
    selectedFiles.toggleSelection(file);
    await tester.pumpAndSettle();
    final sheet = find.byType(SelectionActionSheet);
    final material = find.descendant(
      of: sheet,
      matching: find.byType(Material),
    );
    final handle = find.descendant(
      of: sheet,
      matching: find.bySemanticsLabel("More"),
    );
    await tester.tap(handle);
    await tester.pumpAndSettle();
    await tester.tap(handle);
    await tester.pump();
    for (var frame = 0; frame < 24; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.getBottomRight(material).dy, closeTo(812, 0.01));
      if (frame == 3) await tester.tap(handle);
    }
    selectedFiles.clearAll();
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(tester.takeException(), isNull);
    await _disposeAlbum(tester);
  });

  testWidgets(
    "animates the thumbnail into the header through reversal and cover changes",
    (tester) async {
      late StateSetter refreshAlbums;
      final collection = _collection();
      final oldest = _file(1);
      final newest = _file(2);
      ThumbnailInMemoryLruCache.clearCache(newest);
      ThumbnailInMemoryLruCache.put(
        newest,
        base64Decode(_onePixelPng),
        thumbnailSmallSize,
      );
      await tester.runAsync(() async {
        await FilesDB.instance.insertMultiple([oldest, newest]);
        expect(await CollectionsService.instance.getCover(collection), newest);
        await cachedThumbnailPath(
          newest,
        ).writeAsBytes(base64Decode(_onePixelPng));
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: lightThemeData.copyWith(platform: TargetPlatform.iOS),
          localizationsDelegates: StringsLocalizations.localizationsDelegates,
          supportedLocales: StringsLocalizations.supportedLocales,
          home: StatefulBuilder(
            builder: (context, setState) {
              refreshAlbums = setState;
              return Scaffold(
                body: Align(
                  alignment: Alignment.topLeft,
                  child: AlbumRowItemWidget(collection, 100),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      const heroTag = "collection_1";
      expect(
        tester.widgetList<Hero>(find.byType(Hero)).map((hero) => hero.tag),
        contains(heroTag),
      );

      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is Hero && widget.tag == heroTag,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      final pageFade = find
          .ancestor(
            of: find.byType(CollectionPage),
            matching: find.byType(FadeTransition),
          )
          .first;
      final opacity = tester.widget<FadeTransition>(pageFade).opacity.value;
      expect(opacity, inExclusiveRange(0, 1));
      final flightClip = find.ancestor(
        of: find.byType(RawImage),
        matching: find.byType(ClipSmoothRect),
      );
      final radius = tester.widget<ClipSmoothRect>(flightClip).radius.topLeft.x;
      expect(radius, inExclusiveRange(0, 20));
      Navigator.of(tester.element(find.byType(CollectionPage))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      expect(
        tester.widget<FadeTransition>(pageFade).opacity.value,
        lessThan(opacity),
      );
      expect(
        tester.widget<ClipSmoothRect>(flightClip).radius.topLeft.x,
        greaterThan(radius),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is Hero && widget.tag == heroTag,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      final headerHero = find.descendant(
        of: find.byType(AlbumCoverAppBar),
        matching: find.byType(Hero),
      );
      final provider = InheritedSearchFilterData.of(
        tester.element(headerHero),
      ).searchFilterDataProvider!;
      void refreshRecommendations() => provider.clearAndAddRecommendations([
        FaceFilter(
          personId: null,
          clusterId: "hero-cluster",
          faceName: "Person",
          faceFile: newest,
          occurrence: 2,
        ),
        for (var i = 0; i < 12; i++)
          CameraFilter(cameraModel: "Camera ${i % 10}", occurrence: 1),
      ]);
      var notifications = 0;
      provider.addListener(
        toRecommended: true,
        listener: () => notifications++,
      );
      refreshRecommendations();
      expect(notifications, 1);
      await tester.pump();
      final carousel = find.byType(AppBarFilterChips);
      final face = find.byType(PersonFaceWidget);
      final faceElement = tester.element(face);
      final coverImage = find.descendant(
        of: headerHero,
        matching: find.byType(Image, skipOffstage: false),
        skipOffstage: false,
      );
      final coverImageElement = tester.element(coverImage);
      expect(
        find.descendant(of: headerHero, matching: find.byType(Image)),
        findsNothing,
      );
      expect(
        find.descendant(of: flightClip, matching: carousel),
        findsOneWidget,
      );
      final carouselFade = find
          .descendant(of: carousel, matching: find.byType(FadeTransition))
          .first;
      expect(tester.widget<FadeTransition>(carouselFade).opacity.value, 0);
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        tester.widget<FadeTransition>(carouselFade).opacity.value,
        inExclusiveRange(0, 1),
      );
      final shuttleFade = find
          .ancestor(of: flightClip, matching: find.byType(FadeTransition))
          .first;
      expect(tester.widget<FadeTransition>(shuttleFade).opacity.value, 1);
      await tester.pumpAndSettle();
      expect(tester.element(coverImage), same(coverImageElement));
      expect(tester.element(face), same(faceElement));
      final beforeRefresh = notifications;
      refreshRecommendations();
      expect(notifications, beforeRefresh + 1);
      await tester.pumpAndSettle();
      expect(tester.element(face), same(faceElement));
      final carouselScroll = tester.state<ScrollableState>(
        find.descendant(of: carousel, matching: find.byType(Scrollable)),
      );
      carouselScroll.position.jumpTo(60);
      final galleryScroll = tester
          .state<GalleryBoundariesProviderState>(
            find.byType(GalleryBoundariesProvider),
          )
          .scrollControllerNotifier
          .value!;
      for (final offset in [galleryScroll.position.maxScrollExtent, 0.0]) {
        galleryScroll.jumpTo(offset);
        await tester.pump();
        expect(tester.element(face), same(faceElement));
        expect(carouselScroll.position.pixels, 60);
      }
      await _expectCover(tester, newest, count: 2);
      expect(
        find.descendant(
          of: find.byType(AlbumCoverAppBar),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );

      expect(tester.widget<Hero>(headerHero).tag, heroTag);

      collection.pubMagicMetadata = CollectionPubMagicMetadata(asc: true);
      Bus.instance.fire(
        CollectionMetaEvent(collection.id, CollectionMetaEventType.sortChanged),
      );
      await _expectCover(tester, oldest, count: 2);
      expect(tester.widget<Hero>(headerHero).tag, heroTag);
      Bus.instance.fire(
        CollectionUpdatedEvent(collection.id, [], "cover_change"),
      );
      await tester.pump();
      await tester.runAsync(() async {
        expect(await CollectionsService.instance.getCover(collection), oldest);
      });
      refreshAlbums(() {});
      await _expectCover(tester, oldest, count: 2);
      final albumHero = find.descendant(
        of: find.byType(AlbumRowItemWidget, skipOffstage: false),
        matching: find.byWidgetPredicate(
          (widget) => widget is Hero && widget.child is ClipSmoothRect,
          skipOffstage: false,
        ),
        skipOffstage: false,
      );
      expect(tester.widget<Hero>(albumHero).tag, heroTag);

      await tester.timedDragFrom(
        const Offset(1, 300),
        const Offset(80, 0),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(tester.element(face), same(faceElement));
      expect(carouselScroll.position.pixels, 60);
      Navigator.of(tester.element(find.byType(CollectionPage))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        find.descendant(of: flightClip, matching: carousel),
        findsOneWidget,
      );
      expect(tester.element(face), same(faceElement));
      expect(
        tester.widget<ClipSmoothRect>(flightClip).radius.topLeft.x,
        inExclusiveRange(0, 20),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlbumRowItemWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _disposeAlbum(tester);
    },
  );
  testWidgets(
    "retries failed faces on refresh without reloading loaded faces",
    (tester) async {
      EntePhotosRust.initMock(api: _FakePhotosRustApi());
      MLDataDB.initialize(preferRust: false);
      Future<void> cacheFace(String cluster, int id) async {
        final face = Face.empty(id);
        await cachedFaceCropPath(
          face.faceID,
          false,
        ).writeAsBytes(base64Decode(_onePixelPng));
        await getCachedFaceCrops(
          _file(id),
          [face],
          personOrClusterID: cluster,
          useTempCache: false,
        );
      }

      await tester.runAsync(() => cacheFace("loaded-cluster", 901));
      final provider = SearchFilterDataProvider(
        initialGalleryFilter: CameraFilter(
          cameraModel: "initial",
          occurrence: 100,
        ),
      );
      addTearDown(provider.dispose);
      void refresh([String missing = "failed-cluster"]) =>
          provider.clearAndAddRecommendations([
            for (final cluster in ["loaded-cluster", missing])
              FaceFilter(
                personId: cluster == "pending-person" ? cluster : null,
                clusterId: cluster == "pending-person" ? null : cluster,
                faceName: null,
                faceFile: null,
                occurrence: 1,
              ),
          ]);
      refresh();
      await tester.pumpWidget(
        MaterialApp(
          theme: lightThemeData,
          localizationsDelegates: StringsLocalizations.localizationsDelegates,
          supportedLocales: StringsLocalizations.supportedLocales,
          home: Scaffold(
            body: InheritedSearchFilterData(
              searchFilterDataProvider: provider,
              child: const AppBarFilterChips(animateRecommendations: true),
            ),
          ),
        ),
      );
      Finder face(String cluster) => find.byWidgetPredicate(
        (widget) =>
            widget is PersonFaceWidget &&
            (widget.clusterID == cluster || widget.personId == cluster),
      );
      Future<Uint8List?>? future(String cluster) => tester
          .widget<FutureBuilder<Uint8List?>>(
            find.descendant(
              of: face(cluster),
              matching: find.byType(FutureBuilder<Uint8List?>),
            ),
          )
          .future;
      Future<void> settleFaces(int imageCount) async {
        await tester.runAsync(() async {
          for (var i = 0; i < 100; i++) {
            await tester.pump();
            final images = tester.widgetList<RawImage>(find.byType(RawImage));
            if (find.byType(EnteLoadingWidget).evaluate().isEmpty &&
                images.length == imageCount &&
                images.every((image) => image.image != null)) {
              return;
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        expect(find.byType(EnteLoadingWidget), findsNothing);
        expect(find.byType(RawImage), findsNWidgets(imageCount));
      }

      await settleFaces(1);
      final loadedElement = tester.element(face("loaded-cluster"));
      final loadedFuture = future("loaded-cluster");
      final failedFuture = future("failed-cluster");
      final loadedImage = tester.widget<RawImage>(find.byType(RawImage)).image;
      await tester.runAsync(() => cacheFace("failed-cluster", 902));
      refresh();
      await tester.pump();
      expect(tester.element(face("loaded-cluster")), same(loadedElement));
      expect(future("loaded-cluster"), same(loadedFuture));
      expect(future("failed-cluster"), isNot(same(failedFuture)));
      expect(
        tester
            .widget<RawImage>(
              find.descendant(
                of: face("loaded-cluster"),
                matching: find.byType(RawImage),
              ),
            )
            .image,
        same(loadedImage),
      );
      await settleFaces(2);
      final recoveredFuture = future("failed-cluster");
      refresh();
      await tester.pump();
      expect(future("loaded-cluster"), same(loadedFuture));
      expect(future("failed-cluster"), same(recoveredFuture));
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1,
      );
      final entities = _PendingEntityService();
      PersonService.init(
        entities,
        MLDataDB.instance,
        await SharedPreferences.getInstance(),
      );
      refresh("pending-person");
      await tester.pump();
      final pendingFuture = future("pending-person");
      expect(entities.lookups, 1);
      await tester.runAsync(() => cacheFace("pending-person", 903));
      for (var i = 0; i < 3; i++) {
        refresh("pending-person");
        await tester.pump();
        expect(future("pending-person"), same(pendingFuture));
        expect(future("loaded-cluster"), same(loadedFuture));
        expect(entities.lookups, 1);
      }
      entities.firstLookup.complete(null);
      await settleFaces(2);
      expect(entities.lookups, 2);
      expect(tester.element(face("loaded-cluster")), same(loadedElement));
      refresh("pending-person");
      await tester.pump();
      expect(entities.lookups, 2);
      await _disposeAlbum(tester);
    },
  );
}

Collection _collection({int ownerID = 1}) => Collection(
  1,
  User(id: ownerID, email: "a@b.c"),
  "",
  null,
  "Album",
  null,
  null,
  CollectionType.album,
  CollectionAttributes(),
  [],
  [],
  0,
);

EnteFile _file(int id, {bool uploaded = true}) {
  final file = EnteFile()
    ..generatedID = id
    ..uploadedFileID = uploaded ? id : null
    ..ownerID = 1
    ..collectionID = 1
    ..localID = "local-$id"
    ..title = "$id.jpg"
    ..deviceFolder = "Camera"
    ..fileType = FileType.image
    ..creationTime = DateTime(2026, 1, id).microsecondsSinceEpoch
    ..modificationTime = DateTime(2026, 1, id).microsecondsSinceEpoch;
  final bytes = base64Decode(_onePixelPng);
  ThumbnailInMemoryLruCache.put(file, bytes, thumbnailSmallSize);
  ThumbnailInMemoryLruCache.put(file, bytes, thumbnailLargeSize);
  return file;
}

Future<void> _pumpAlbum(WidgetTester tester, Collection collection) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: lightThemeData,
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      supportedLocales: StringsLocalizations.supportedLocales,
      home: CollectionPage(CollectionWithThumbnail(collection, null)),
    ),
  );
}

Future<void> _expectCover(
  WidgetTester tester,
  EnteFile? file, {
  int? count,
}) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      final covers = tester.widgetList<AlbumCoverAppBar>(
        find.byType(AlbumCoverAppBar),
      );
      final hasExpectedCover = file == null
          ? covers.isEmpty
          : covers.singleOrNull?.cover == file;
      final hasExpectedCount =
          count == null ||
          tester
                  .widget<GalleryFilesState>(find.byType(GalleryFilesState))
                  .galleryFilesOrNull
                  ?.length ==
              count;
      if (hasExpectedCover && hasExpectedCount) {
        await tester.pump(const Duration(seconds: 1));
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
  final covers = tester.widgetList<AlbumCoverAppBar>(
    find.byType(AlbumCoverAppBar),
  );
  expect(covers.map((cover) => cover.cover), file == null ? isEmpty : [file]);
  if (count != null) {
    expect(
      tester
          .widget<GalleryFilesState>(find.byType(GalleryFilesState))
          .galleryFilesOrNull
          ?.length,
      count,
    );
  }
  expect(tester.takeException(), isNull);
}

Future<void> _disposeAlbum(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

class _CountingFile extends EnteFile {
  _CountingFile(super.file) : super.from();

  int creationTimeReads = 0;

  @override
  int? get creationTime {
    creationTimeReads++;
    return super.creationTime;
  }
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

const _onePixelPng =
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==";

class _FakePhotosRustApi extends Fake implements EntePhotosRustApi {
  @override
  bool crateApiMlDbApiDecideMlDbBackend({required bool preferRust}) => false;
}

class _PendingEntityService extends Fake implements EntityService {
  final firstLookup = Completer<LocalEntityData?>();
  int lookups = 0;

  @override
  int lastSyncTime(EntityType type) => 0;

  @override
  Future<LocalEntityData?> getEntity(EntityType type, String id) async {
    if (++lookups == 1) return firstLookup.future;
    return LocalEntityData(
      id: id,
      type: type,
      data: jsonEncode(PersonData(name: "Person").toJson()),
      ownerID: 1,
      updatedAt: 1,
    );
  }
}
