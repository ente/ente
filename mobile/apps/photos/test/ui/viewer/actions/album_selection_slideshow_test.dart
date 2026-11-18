import "dart:async";
import "dart:io";

import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/core/configuration.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/ignored_files_db.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/metadata/collection_magic.dart";
import "package:photos/models/selected_albums.dart";
import "package:photos/ui/collections/collection_list_page.dart";
import "package:photos/ui/viewer/actions/album_selection_action_widget.dart";
import "package:photos/ui/viewer/album_slideshow/album_slideshow_page.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const paths = MethodChannel("plugins.flutter.io/path_provider");

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp("album_slideshow_sort_");
    messenger.setMockMethodCallHandler(paths, (_) async => directory.path);
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({Configuration.userIDKey: 1});
    await Configuration.instance.init(await SharedPreferences.getInstance());
    await FilesDB.instance.insertMultiple([
      _file(1, 10, "photo10.jpg", 100),
      _file(2, 10, "photo2.jpg", 200),
      _file(3, 20, "image2.jpg", 200),
      _file(4, 20, "image10.jpg", 100),
      _file(2, 20, "photo2.jpg", 300),
      _file(5, 30, "z.jpg", 100),
      _file(6, 30, "a.jpg", 200),
      _file(7, 40, "a.jpg", 100),
      _file(8, 40, "z.jpg", 200),
    ]);
  });

  tearDownAll(() async {
    await (await FilesDB.instance.sqliteAsyncDB).close();
    await (await IgnoredFilesDB.instance.database).close();
    messenger.setMockMethodCallHandler(paths, null);
    await directory.delete(recursive: true);
  });

  testWidgets("album selection slideshow keeps each album's saved order", (
    tester,
  ) async {
    final selected = SelectedAlbums()
      ..select({
        _album(10, asc: true, sortBy: "fileName"),
        _album(20, asc: false, sortBy: "fileName"),
        _album(30, asc: true),
        _album(40),
      });
    addTearDown(selected.dispose);
    final observer = _SlideshowObserver();
    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: StringsLocalizations.supportedLocales,
        navigatorObservers: [observer],
        home: Scaffold(
          body: Stack(
            children: [
              AlbumSelectionActionWidget(
                selected,
                UISectionType.homeCollections,
                selectionControls: const SizedBox(height: 48),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() => tester.tap(find.text("Slideshow")));
    for (var attempt = 0; attempt < 100 && observer.page == null; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(observer.page, isNotNull);
    expect(observer.page!.files.map((file) => file.uploadedFileID), [
      2,
      1,
      4,
      3,
      5,
      6,
      8,
      7,
    ]);
    expect(observer.page!.title, "Slideshow");
    await tester.pumpAndSettle();
    expect(selected.albums, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

EnteFile _file(int id, int album, String title, int time) => EnteFile()
  ..uploadedFileID = id
  ..ownerID = 1
  ..collectionID = album
  ..title = title
  ..fileType = FileType.image
  ..creationTime = time
  ..modificationTime = time;

Collection _album(int id, {bool? asc, String? sortBy}) => Collection(
  id,
  User(id: 1, email: "test@example.com"),
  "",
  null,
  "Album $id",
  null,
  null,
  CollectionType.album,
  CollectionAttributes(),
  [],
  [],
  0,
)..pubMagicMetadata = CollectionPubMagicMetadata(asc: asc, sortBy: sortBy);

class _SlideshowObserver extends NavigatorObserver {
  AlbumSlideshowPage? page;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRouteBuilder) return;
    final widget = route.pageBuilder(
      navigator!.context,
      const AlwaysStoppedAnimation(1),
      const AlwaysStoppedAnimation(0),
    );
    if (widget is AlbumSlideshowPage) {
      page = widget;
      scheduleMicrotask(() => navigator!.removeRoute(route));
    }
  }
}
