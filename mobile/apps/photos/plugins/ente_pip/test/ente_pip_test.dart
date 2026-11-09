import "dart:async";
import "dart:io";

import "package:ente_pip/ente_pip.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel("io.ente.photos/pip");
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late List<MethodCall> calls;
  late Directory tempDir;

  Future<void> nativeHolds(List<String> paths) =>
      EntePip.handleNativeCall(MethodCall("held", {"paths": paths}));

  Future<void> startPip(String path) => EntePip.start(
    path: path,
    position: Duration.zero,
    muted: false,
    speed: 1,
    loop: false,
  );

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() async {
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    await nativeHolds([]);
    tempDir = Directory.systemTemp.createTempSync("ente_pip_test");
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    tempDir.deleteSync(recursive: true);
  });

  File tempVideo(String name) => File("${tempDir.path}/$name")..createSync();

  test("start sends the playback state the native player needs", () async {
    await EntePip.start(
      path: "/tmp/video.mp4",
      position: const Duration(seconds: 12, milliseconds: 345),
      muted: true,
      speed: 1.5,
      loop: true,
    );

    expect(calls.single.method, "start");
    expect(calls.single.arguments, {
      "path": "/tmp/video.mp4",
      "positionMs": 12345,
      "muted": true,
      "speed": 1.5,
      "loop": true,
    });
  });

  test("a stream is sent as its playlist, named by path", () async {
    await EntePip.start(
      path: "/tmp/42.m3u8",
      position: Duration.zero,
      muted: false,
      speed: 1,
      loop: false,
      hlsPlaylist: "#EXTM3U",
    );

    expect(calls.single.arguments, containsPair("path", "/tmp/42.m3u8"));
    expect(calls.single.arguments, containsPair("hlsPlaylist", "#EXTM3U"));
  });

  test("closing the viewer keeps the file PiP is playing", () async {
    final video = tempVideo("playing.mp4");
    EntePip.useFile(video.path); // viewer opens
    await startPip(video.path);
    await nativeHolds([video.path]);

    EntePip.deleteWhenUnused(video.path); // viewer dispose()
    await settle();
    expect(video.existsSync(), isTrue);

    await nativeHolds([]); // PiP closed
    await settle();
    expect(video.existsSync(), isFalse);
  });

  test("a viewer reopened at the same path keeps its file", () async {
    // iOS hands out the same temporary copy for the same video, so the
    // viewer opened by "back to video" plays the path PiP is releasing.
    final video = tempVideo("same_path.mp4");
    EntePip.useFile(video.path);
    await startPip(video.path);
    await nativeHolds([video.path]);
    EntePip.deleteWhenUnused(video.path); // first viewer closed

    EntePip.useFile(video.path); // "back to video" opens a new viewer
    await nativeHolds([]); // PiP hands back and closes
    await settle();
    expect(video.existsSync(), isTrue);

    EntePip.deleteWhenUnused(video.path); // new viewer closed
    await settle();
    expect(video.existsSync(), isFalse);
  });

  test("closing PiP keeps a file another viewer still uses", () async {
    final video = tempVideo("shared.mp4");
    EntePip.useFile(video.path); // viewer A
    EntePip.useFile(video.path); // viewer B of the same video
    await startPip(video.path);
    await nativeHolds([video.path]);

    EntePip.deleteWhenUnused(video.path); // viewer A closed
    await nativeHolds([]); // PiP closed, viewer B still open
    await settle();
    expect(video.existsSync(), isTrue);

    EntePip.deleteWhenUnused(video.path); // viewer B closed
    await settle();
    expect(video.existsSync(), isFalse);
  });

  test("a file is protected from the moment start is called", () async {
    final video = tempVideo("starting.mp4");
    final reply = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (_) => reply.future);

    final start = startPip(video.path);
    EntePip.deleteWhenUnused(video.path); // viewer closed during the tap
    await settle();
    expect(video.existsSync(), isTrue);

    reply.completeError(PlatformException(code: "START_FAILED"));
    await expectLater(start, throwsA(isA<PlatformException>()));
    await settle();
    expect(video.existsSync(), isFalse);
  });

  test("an unused file is deleted right away", () async {
    final video = tempVideo("unused.mp4");
    EntePip.deleteWhenUnused(video.path);
    await settle();
    expect(video.existsSync(), isFalse);
  });

  group("back to video", () {
    const restoreCall = MethodCall("restore", {
      "path": "/tmp/a.mp4",
      "positionMs": 4200,
    });
    final handlers = <PipRestoreHandler>[];

    void addHandler(PipRestoreHandler handler) {
      handlers.add(handler);
      EntePip.addRestoreHandler(handler);
    }

    tearDown(() {
      handlers.forEach(EntePip.removeRestoreHandler);
      handlers.clear();
      EntePip.fallbackRestoreHandler = null;
    });

    test("the open viewer showing the video continues it", () async {
      PipRestore? continued;
      var fallbackAsked = false;
      addHandler((restore) {
        continued = restore;
        return true;
      });
      EntePip.fallbackRestoreHandler = (_) => fallbackAsked = true;

      expect(await EntePip.handleNativeCall(restoreCall), isTrue);
      expect(continued?.path, "/tmp/a.mp4");
      expect(continued?.position, const Duration(milliseconds: 4200));
      expect(fallbackAsked, isFalse);
    });

    test("without such a viewer, the fallback opens one", () async {
      addHandler((_) => false); // e.g. the viewer of another video
      EntePip.fallbackRestoreHandler = (_) => true;

      expect(await EntePip.handleNativeCall(restoreCall), isTrue);
    });

    test("when nobody can show it, iOS is told to just close", () async {
      addHandler((_) => false);
      EntePip.fallbackRestoreHandler = (_) => false;

      expect(await EntePip.handleNativeCall(restoreCall), isFalse);
    });

    test("the most recently opened viewer is asked first", () async {
      final asked = <String>[];
      addHandler((_) {
        asked.add("older");
        return true;
      });
      addHandler((_) {
        asked.add("newer");
        return true;
      });

      await EntePip.handleNativeCall(restoreCall);
      expect(asked, ["newer"]);
    });
  });

  test("stop closes the PiP window", () async {
    await EntePip.stop();
    expect(calls.single.method, "stop");
  });

  test("isSupported is false when the plugin is not registered", () async {
    messenger.setMockMethodCallHandler(channel, null);
    expect(await EntePip.invokeIsSupported(), isFalse);
  });

  test("isSupported is false outside iOS", () async {
    expect(await EntePip.isSupported(), isFalse);
    expect(calls, isEmpty);
  });
}
