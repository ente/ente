import "dart:convert";
import "dart:io";

import "package:dio/dio.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:figma_squircle/figma_squircle.dart";
import "package:flutter/material.dart";
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
import "package:photos/ente_theme_data.dart";
import "package:photos/events/collection_meta_event.dart";
import "package:photos/events/collection_updated_event.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/collection/collection_items.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/gallery_type.dart";
import "package:photos/models/ignored_file.dart";
import "package:photos/models/metadata/collection_magic.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/module/download/thumbnail.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/app_navigation_service.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/favorites_service.dart";
import "package:photos/services/ignored_files_service.dart";
import "package:photos/ui/collections/album/row_item.dart";
import "package:photos/ui/components/bottom_action_bar/action_bar_widget.dart";
import "package:photos/ui/viewer/actions/file_selection_overlay_bar.dart";
import "package:photos/ui/viewer/gallery/collection_page.dart";
import "package:photos/ui/viewer/gallery/component/album_cover_app_bar.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/gallery_app_bar_widget.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
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
      expect(find.byTooltip("Sort"), findsOneWidget);
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
      expect(find.byTooltip("Sort"), findsOneWidget);

      collection.pubMagicMetadata = CollectionPubMagicMetadata(asc: true);
      Bus.instance.fire(
        CollectionMetaEvent(collection.id, CollectionMetaEventType.sortChanged),
      );
      await _expectCover(tester, oldest, count: 2);
      expect(find.text("1–3 JAN 2026"), findsOneWidget);

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
      await _disposeAlbum(tester);
      selectedFiles.dispose();
    },
  );

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
      await tester.pumpAndSettle();
      await _expectCover(tester, newest, count: 2);
      expect(
        find.descendant(
          of: find.byType(AlbumCoverAppBar),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
      final headerHero = find.descendant(
        of: find.byType(AlbumCoverAppBar),
        matching: find.byType(Hero),
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

      Navigator.of(tester.element(find.byType(CollectionPage))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(AlbumRowItemWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _disposeAlbum(tester);
    },
  );
}

Collection _collection() => Collection(
  1,
  User(id: 1, email: "a@b.c"),
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
