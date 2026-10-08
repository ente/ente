import "dart:async";
import "dart:convert";
import "dart:io";

import "package:dio/dio.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
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

  Future<void> openMemory(WidgetTester tester) async {
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
            child: const FullScreenMemory(
              "Memory",
              0,
              memoryID: "memory",
              isActive: true,
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
