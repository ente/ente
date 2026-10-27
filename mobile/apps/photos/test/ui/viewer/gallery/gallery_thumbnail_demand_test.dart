import "dart:async";
import "dart:convert";
import "dart:io";

import "package:dio/dio.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_secure_storage/flutter_secure_storage.dart";
import "package:flutter_test/flutter_test.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:photos/core/cache/thumbnail_in_memory_cache.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/network/network.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/file_load_result.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/favorites_service.dart";
import "package:photos/settings/local_settings.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/ui/viewer/gallery/gallery.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform previousPathProvider;
  late _HeldThumbnailDownloads downloads;
  late Dio serviceDio;
  const userAgentChannel = MethodChannel("ua_client_hints");

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp("gallery_thumbnails_");
    previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory.path);
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      "remote_flags": '{"disableCFWorker":true}',
      "ls.internal_user_disabled": true,
    });
    final preferences = await SharedPreferences.getInstance();
    final info = PackageInfo(
      appName: "Photos",
      packageName: "photos",
      version: "1.0.0",
      buildNumber: "1",
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          userAgentChannel,
          (_) async => <String, String>{"appName": "Photos", "version": "1"},
        );
    serviceDio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) => handler.resolve(
            Response(
              requestOptions: options,
              data: <String, dynamic>{"disableCFWorker": true},
            ),
          ),
        ),
      );
    ServiceLocator.instance.init(
      preferences,
      serviceDio,
      serviceDio,
      serviceDio,
      info,
    );
    await Configuration.instance.init(preferences);
    await Configuration.instance.setUserID(1);
    await Configuration.instance.setToken("test-token");
    await FavoritesService.instance.initFav();
    await NetworkClient.instance.init(info, preferences);
    downloads = _HeldThumbnailDownloads();
    for (final dio in [
      NetworkClient.instance.enteDio,
      NetworkClient.instance.downloadDio,
    ]) {
      dio.interceptors.clear();
      dio.httpClientAdapter = downloads;
    }
  });

  tearDownAll(() async {
    NetworkClient.instance.enteDio.close(force: true);
    NetworkClient.instance.downloadDio.close(force: true);
    NetworkClient.instance.getDio().close(force: true);
    serviceDio.close(force: true);
    FavoritesService.instance.dispose();
    ThumbnailInMemoryLruCache.clearAll();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(userAgentChannel, null);
    PathProviderPlatform.instance = previousPathProvider;
    await directory.delete(recursive: true);
  });

  testWidgets("pinching starts no new thumbnails in covered galleries", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await localSettings.setGalleryLayoutType(GalleryLayoutType.grid);
    await localSettings.setPhotoGridSize(4);
    ThumbnailInMemoryLruCache.clearAll();
    expect(
      Directory(Configuration.instance.getThumbnailCacheDirectory()).listSync(),
      isEmpty,
    );

    final navigation = GlobalKey<NavigatorState>();
    final keys = List.generate(3, (_) => GlobalKey<GalleryState>());
    final files = List.generate(
      3,
      (gallery) => List.generate(
        200,
        (index) => EnteFile()
          ..generatedID = gallery * 1000 + index + 1
          ..uploadedFileID = gallery * 1000 + index + 1
          ..ownerID = 1
          ..collectionID = 1
          ..creationTime = DateTime(2026, 10, 1).microsecondsSinceEpoch
          ..fileType = FileType.image
          ..title = "photo-$gallery-$index.jpg",
      ),
    );
    Widget galleryPage(int index) => GalleryBoundariesProvider(
      child: GalleryFilesState(
        child: Gallery(
          key: keys[index],
          asyncLoader: (start, end, {limit, asc}) async =>
              FileLoadResult(files[index], false),
          tagPrefix: "thumbnails_$index",
          enableFileGrouping: false,
          showSelectAll: false,
        ),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigation,
        theme: lightThemeData.copyWith(platform: TargetPlatform.iOS),
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: StringsLocalizations.supportedLocales,
        home: galleryPage(0),
      ),
    );
    await _waitForMountedThumbnails(tester, downloads);
    for (var index = 1; index < keys.length; index++) {
      unawaited(
        navigation.currentState!.push<void>(
          MaterialPageRoute(builder: (_) => galleryPage(index)),
        ),
      );
      await _waitForMountedThumbnails(tester, downloads);
    }

    List<int> requestCounts() => List.generate(
      keys.length,
      (gallery) =>
          downloads.requestedIDs.where((id) => id ~/ 1000 == gallery).length,
    );
    final before = requestCounts();
    expect(before, everyElement(greaterThan(0)));
    expect(downloads.pendingIDs.where((id) => id < 2000), isNotEmpty);

    final first = await tester.startGesture(const Offset(115, 400), pointer: 1);
    final second = await tester.startGesture(
      const Offset(275, 400),
      pointer: 2,
    );
    await tester.pump();
    await first.moveTo(const Offset(155, 400));
    await second.moveTo(const Offset(235, 400));
    await tester.pump();
    await first.up();
    await second.up();
    await _waitForMountedThumbnails(tester, downloads);

    expect(keys.last.currentState!.galleryGroups!.crossAxisCount, 6);
    expect(requestCounts().last, greaterThan(before.last));
    expect(requestCounts().take(2), orderedEquals(before.take(2)));
    await tester.pump(const Duration(seconds: 5));
    await _waitForMountedThumbnails(tester, downloads);
    expect(requestCounts().take(2), orderedEquals(before.take(2)));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}

Future<void> _waitForMountedThumbnails(
  WidgetTester tester,
  _HeldThumbnailDownloads downloads,
) async {
  await tester.pumpAndSettle();
  final ids = tester
      .widgetList<ThumbnailWidget>(
        find.byType(ThumbnailWidget, skipOffstage: false),
      )
      .map((widget) => widget.file.uploadedFileID!)
      .toSet();
  expect(ids, isNotEmpty);
  final deadline = Stopwatch()..start();
  // Cache checks use real I/O; thumbnail delays use the test clock.
  while (!downloads.startedIDs.containsAll(ids) &&
      deadline.elapsed < const Duration(seconds: 5)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(downloads.startedIDs, containsAll(ids));
}

class _HeldThumbnailDownloads implements HttpClientAdapter {
  final requestedIDs = <int>[];
  final startedIDs = <int>{};
  final _pending = <Completer<ResponseBody>, RequestOptions>{};

  Iterable<int> get pendingIDs => _pending.values.map(
    (options) => int.parse(options.uri.pathSegments.last),
  );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final id = int.parse(options.uri.pathSegments.last);
    if (options.uri.path.startsWith("/files/thumbnail/v3/")) {
      requestedIDs.add(id);
      return ResponseBody.fromString(
        jsonEncode({"url": "https://thumbnail.test/$id"}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    expect(options.uri.host, "thumbnail.test");
    final response = Completer<ResponseBody>();
    _pending[response] = options;
    startedIDs.add(id);
    unawaited(cancelFuture?.then((_) => _cancel(response)));
    return response.future;
  }

  void _cancel(Completer<ResponseBody> response) {
    final options = _pending.remove(response);
    if (options != null) {
      response.completeError(
        DioException(requestOptions: options, type: DioExceptionType.cancel),
      );
    }
  }

  @override
  void close({bool force = false}) {
    for (final response in _pending.keys.toList()) {
      _cancel(response);
    }
  }
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getApplicationSupportPath() async => path;

  @override
  Future<String?> getTemporaryPath() async => path;
}
