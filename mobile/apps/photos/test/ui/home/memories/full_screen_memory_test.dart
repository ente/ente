import "dart:async";
import "dart:convert";
import "dart:io";

import "package:dio/dio.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:image/image.dart" as img;
import "package:package_info_plus/package_info_plus.dart";
import "package:photos/core/cache/image_cache.dart";
import "package:photos/core/cache/thumbnail_in_memory_cache.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/events/details_sheet_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/memory_music_track.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/memories/memory_music_controller.dart";
import "package:photos/services/memories/memory_music_player.dart";
import "package:photos/ui/home/memories/full_screen_memory.dart";
import "package:photos/ui/home/memories/memory_music_session.dart";
import "package:photos/ui/notification/update/change_log_page.dart";
import "package:photos/ui/viewer/file/file_widget.dart";
import "package:photos/ui/viewer/file/image_zoom/image_zoom_viewer.dart";
import "package:photos/ui/viewer/file/image_zoom/viewer_jpeg_image.dart";
import "package:shared_preferences/shared_preferences.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final imageBytes = base64Decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==",
  );
  late Directory directory;
  late File imageFile;
  late EnteFile file;
  late ValueNotifier<int> indexNotifier;
  late _MemoryMusicPlayer player;
  late MemoryMusicController music;
  const track = MemoryMusicTrack(
    id: "track",
    url: "https://example.com/track.mp3",
  );

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
    // Configuration stores preferences before initializing native plugins.
    try {
      await Configuration.instance.init(preferences);
    } on MissingPluginException catch (_) {}

    directory = Directory.systemTemp.createTempSync("memory_popup_test");
    imageFile = File("${directory.path}/photo.png")
      ..writeAsBytesSync(imageBytes);
  });

  tearDownAll(() => directory.deleteSync(recursive: true));

  setUp(() {
    file = EnteFile()
      ..generatedID = 1
      ..localID = "memory-photo"
      ..fileType = FileType.image
      ..title = "photo.png"
      ..creationTime = DateTime(2026).microsecondsSinceEpoch;
    ThumbnailInMemoryLruCache.put(file, imageBytes, thumbnailSmallSize);
    ThumbnailInMemoryLruCache.put(file, imageBytes, thumbnailLargeSize);
    FileLruCache.put("${file.tag}falsefalse", imageFile);
    indexNotifier = ValueNotifier(0);
    player = _MemoryMusicPlayer();
    music = MemoryMusicController(
      assignments: const {"memory": track},
      initiallyMuted: false,
      persistMuted: (_) async {},
      player: player,
      tracks: const [track],
    );
  });

  tearDown(() {
    music.dispose();
    indexNotifier.dispose();
    ThumbnailInMemoryLruCache.clearAll();
    FileLruCache.clearAll();
  });

  Future<void> openMemory(WidgetTester tester, {bool isActive = true}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: StringsLocalizations.supportedLocales,
        home: MemoryAudioScope(
          controller: music,
          isMusicMuted: false,
          isVideoMuted: false,
          toggleMusicMuted: () async {},
          toggleVideoMuted: () async {},
          child: FullScreenMemoryData(
            memories: [Memory(file, -1)],
            indexNotifier: indexNotifier,
            removeCurrentMemory: () {},
            preloadThumbnail: (_) {},
            preloadVideos: (_) {},
            child: FullScreenMemory(
              "Memory",
              0,
              memoryID: "memory",
              isActive: isActive,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  double progress(WidgetTester tester) => tester
      .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
      .value!;

  List<double> zoom(WidgetTester tester) => tester
      .widget<Transform>(
        find
            .descendant(
              of: find.byType(MemoriesZoomWidget),
              matching: find.byType(Transform),
            )
            .first,
      )
      .transform
      .storage
      .toList();

  FileWidget media(WidgetTester tester) =>
      tester.widget<FileWidget>(find.byType(FileWidget));

  testWidgets("a held memory pinch sharpens until the last finger lifts", (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(720, 1440);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final jpeg = File("${directory.path}/portrait.jpg")
      ..writeAsBytesSync(img.encodeJpg(img.Image(width: 1200, height: 1600)));
    file.title = "portrait.jpg";
    FileLruCache.put("${file.tag}falsefalse", jpeg);
    final fit = ViewerJpegImage.fit(jpeg, const Size(720, 1440) * 1.15);
    final detail = FileImage(jpeg);
    final viewerFinder = find.byType(ImageZoomViewer);
    ImageZoomViewer viewer() => tester.widget<ImageZoomViewer>(viewerFinder);
    Future<void> waitFor(ImageProvider expected) async {
      final image = find.descendant(
        of: viewerFinder,
        matching: find.image(expected),
      );
      for (var i = 0; i < 100 && image.evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(image, findsOneWidget);
    }

    await openMemory(tester, isActive: false);
    await waitFor(MemoryImage(imageBytes));
    expect(imageCache.statusForKey(fit).untracked, isTrue);
    expect(imageCache.statusForKey(detail).untracked, isTrue);
    await openMemory(tester);
    await waitFor(fit);
    final preview = viewer().imageProvider;
    final startZoom = zoom(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(zoom(tester), isNot(startZoom));
    expect(viewer().imageProvider, same(preview));
    expect(imageCache.statusForKey(detail).untracked, isTrue);

    final center = tester.getCenter(viewerFinder);
    const radius = Offset(35, 0);
    final quickLeft = await tester.startGesture(center - radius);
    final quickRight = await tester.startGesture(center + radius);
    await quickRight.moveBy(radius);
    await tester.pump(const Duration(milliseconds: 50));
    await quickLeft.up();
    await quickRight.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(viewer().controller!.isZoomed, isFalse);
    expect(imageCache.statusForKey(detail).untracked, isTrue);

    final left = await tester.startGesture(center - radius);
    final right = await tester.startGesture(center + radius);
    await left.moveTo(center - radius * 2);
    await right.moveTo(center + radius * 2);
    await tester.pump();
    expect(viewer().controller!.isZoomed, isTrue);
    final pausedProgress = progress(tester);
    for (var i = 0; i < 12; i++) {
      await right.moveBy(const Offset(3, 0));
      await tester.pump(const Duration(milliseconds: 30));
    }
    expect(imageCache.statusForKey(detail).untracked, isTrue);
    for (var i = 0; i < 3; i++) {
      await right.moveBy(const Offset(0.3, 1));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await left.up();
    await tester.pump(const Duration(milliseconds: 110));
    expect(imageCache.statusForKey(detail).untracked, isFalse);
    final extraFinger = await tester.startGesture(center - radius);
    await right.moveBy(radius);
    await tester.pump();
    await waitFor(detail);
    await extraFinger.up();
    expect(progress(tester), pausedProgress);
    expect(viewer().controller!.isZoomed, isTrue);
    await right.up();
    await tester.pump();
    await tester.pump(viewer().animationDuration);
    expect(viewer().controller!.isZoomed, isFalse);
    expect(progress(tester), greaterThan(pausedProgress));
    await waitFor(fit);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  });

  testWidgets("What's New pauses memories and resumes from the same point", (
    tester,
  ) async {
    await openMemory(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(progress(tester), greaterThan(0));
    expect(player.playing, isTrue);

    unawaited(
      showChangeLogSheet(tester.element(find.byType(FullScreenMemory))),
    );
    await tester.pump();
    final pausedProgress = progress(tester);
    final pausedZoom = zoom(tester);
    expect(media(tester).isActive, isFalse);
    expect(player.playing, isFalse);

    await tester.pump(const Duration(seconds: 6));
    expect(progress(tester), pausedProgress);
    expect(zoom(tester), pausedZoom);

    Navigator.of(tester.element(find.byType(ChangeLogPage))).pop();
    await tester.pump();
    expect(progress(tester), pausedProgress);
    expect(media(tester).isActive, isTrue);
    expect(player.playing, isTrue);
    expect(player.loads, 1);
    await tester.pump(const Duration(milliseconds: 100));
    expect(progress(tester), greaterThan(pausedProgress));
    expect(zoom(tester), isNot(pausedZoom));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets("ready media respects the popup and existing viewer pause", (
    tester,
  ) async {
    final loadCompleted = Completer<void>();
    player.loadCompleted = loadCompleted.future;
    await openMemory(tester);
    unawaited(
      showChangeLogSheet(tester.element(find.byType(FullScreenMemory))),
    );
    await tester.pump();

    media(tester).onFinalFileLoad!(memoryDuration: 5);
    loadCompleted.complete();
    await tester.pump();
    await tester.pump(const Duration(seconds: 6));
    expect(progress(tester), 0);
    expect(media(tester).isActive, isFalse);
    expect(player.playing, isFalse);

    Bus.instance.fire(
      DetailsSheetEvent(
        localID: file.localID,
        uploadedFileID: file.uploadedFileID,
        opened: true,
      ),
    );
    await tester.pump();
    Navigator.of(tester.element(find.byType(ChangeLogPage))).pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(progress(tester), 0);
    expect(media(tester).isActive, isFalse);
    expect(player.playing, isFalse);

    Bus.instance.fire(
      DetailsSheetEvent(
        localID: file.localID,
        uploadedFileID: file.uploadedFileID,
        opened: false,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(media(tester).isActive, isTrue);
    expect(player.playing, isTrue);
    await tester.pump(const Duration(milliseconds: 100));
    expect(progress(tester), greaterThan(0));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 20));
  });
}

class _MemoryMusicPlayer implements MemoryMusicPlayer {
  bool playing = false;
  int loads = 0;
  Future<void>? loadCompleted;

  @override
  Future<void> configureAudioSession() async {}

  @override
  Future<void> load(MemoryMusicTrack track) async {
    loads++;
    await loadCompleted;
  }

  @override
  Future<void> play() async => playing = true;

  @override
  Future<void> playImmediately() => play();

  @override
  Future<void> pause() async => playing = false;

  @override
  Future<void> pauseImmediately() => pause();

  @override
  Future<void> dispose() async {}
}
