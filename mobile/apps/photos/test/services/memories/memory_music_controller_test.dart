import "dart:async";

import "package:flutter_test/flutter_test.dart";
import "package:photos/models/memories/memory_music_track.dart";
import "package:photos/services/memories/memory_music_controller.dart";
import "package:photos/services/memories/memory_music_player.dart";

void main() {
  const track1 = MemoryMusicTrack(
    id: "track-1",
    url: "https://example.com/track-1.mp3",
    cacheFileName: "track-1.mp3",
  );
  const track2 = MemoryMusicTrack(
    id: "track-2",
    url: "https://example.com/track-2.mp3",
    cacheFileName: "track-2.mp3",
  );
  late _FakeMemoryMusicPlayer player;
  late List<bool> persistedMuteValues;
  late MemoryMusicController controller;

  MemoryMusicController createController({bool initiallyMuted = false}) {
    return MemoryMusicController(
      assignments: const <String, MemoryMusicTrack>{
        "memory-1": track1,
        "memory-2": track2,
      },
      initiallyMuted: initiallyMuted,
      persistMuted: (value) async => persistedMuteValues.add(value),
      player: player,
      tracks: const <MemoryMusicTrack>[track1, track2],
    );
  }

  setUp(() {
    player = _FakeMemoryMusicPlayer();
    persistedMuteValues = <bool>[];
    controller = createController();
  });

  tearDown(() {
    controller.dispose();
  });

  test("activating a photo memory loads, loops, and plays its track", () async {
    await controller.activateMemory("memory-1", currentItemIsVideo: false);

    expect(player.loadedTracks.map((track) => track.id), <String>["track-1"]);
    expect(player.looping, isTrue);
    expect(player.playing, isTrue);
  });

  test("video items pause music and photos resume it", () async {
    await controller.activateMemory("memory-1", currentItemIsVideo: false);

    await controller.activateMemory("memory-1", currentItemIsVideo: true);
    expect(player.playing, isFalse);

    await controller.activateMemory("memory-1", currentItemIsVideo: false);
    expect(player.playing, isTrue);
    expect(player.loadAttempts, 1);
  });

  test("initial mute state prevents playback", () async {
    controller.dispose();
    player = _FakeMemoryMusicPlayer();
    controller = createController(initiallyMuted: true);

    await controller.activateMemory("memory-1", currentItemIsVideo: false);

    expect(player.playing, isFalse);
  });

  test("mute pauses music and unmute resumes it", () async {
    await controller.activateMemory("memory-1", currentItemIsVideo: false);

    await controller.toggleMuted();
    expect(player.playing, isFalse);
    expect(player.pausedImmediately, isTrue);
    expect(persistedMuteValues, <bool>[true]);

    await controller.toggleMuted();
    expect(player.playing, isTrue);
    expect(player.playedImmediately, isTrue);
    expect(persistedMuteValues, <bool>[true, false]);
  });

  test("mute and video independently keep music paused", () async {
    await controller.activateMemory("memory-1", currentItemIsVideo: true);
    await controller.toggleMuted();

    await controller.activateMemory("memory-2", currentItemIsVideo: false);
    expect(player.playing, isFalse);

    await controller.activateMemory("memory-2", currentItemIsVideo: true);
    await controller.toggleMuted();
    expect(player.playing, isFalse);

    await controller.activateMemory("memory-2", currentItemIsVideo: false);
    expect(player.playing, isTrue);
  });

  test("changing memories loads the assigned track", () async {
    await controller.activateMemory("memory-1", currentItemIsVideo: false);
    await controller.activateMemory("memory-2", currentItemIsVideo: false);

    expect(player.loadedTracks.map((track) => track.id), <String>[
      "track-1",
      "track-2",
    ]);
  });

  test("newer memory wins when activations overlap", () async {
    final firstLoadStarted = Completer<void>();
    final releaseFirstLoad = Completer<void>();
    player.beforeNextLoadCompletes = () {
      firstLoadStarted.complete();
      return releaseFirstLoad.future;
    };

    final firstActivation = controller.activateMemory(
      "memory-1",
      currentItemIsVideo: false,
    );
    await firstLoadStarted.future;
    await controller.activateMemory("memory-2", currentItemIsVideo: false);
    releaseFirstLoad.complete();
    await firstActivation;

    expect(player.loadedTracks.map((track) => track.id), <String>[
      "track-1",
      "track-2",
    ]);
    expect(player.playAttempts, 1);
  });

  test("music resumes only after every pause reason clears", () async {
    await controller.activateMemory("memory-1", currentItemIsVideo: false);

    await controller.setAppActive(false);
    expect(player.playing, isFalse);
    expect(player.pausedImmediately, isTrue);

    await controller.setViewerActionPaused(true);
    await controller.setAppActive(true);
    expect(player.playing, isFalse);

    await controller.setViewerActionPaused(false);
    expect(player.playing, isTrue);
  });

  test("a failed track uses another track for the session", () async {
    player.failedTrackIDs.add("track-1");

    await controller.activateMemory("memory-1", currentItemIsVideo: false);
    await controller.activateMemory("memory-2", currentItemIsVideo: false);
    await controller.activateMemory("memory-1", currentItemIsVideo: false);

    expect(player.attemptedTracks.map((track) => track.id), <String>[
      "track-1",
      "track-2",
      "track-2",
      "track-2",
    ]);
    expect(player.playing, isTrue);
  });
}

class _FakeMemoryMusicPlayer implements MemoryMusicPlayer {
  final List<MemoryMusicTrack> attemptedTracks = <MemoryMusicTrack>[];
  final List<MemoryMusicTrack> loadedTracks = <MemoryMusicTrack>[];
  bool looping = false;
  bool playing = false;
  bool playedImmediately = false;
  bool pausedImmediately = false;
  final Set<String> failedTrackIDs = <String>{};
  int loadAttempts = 0;
  int playAttempts = 0;
  Future<void> Function()? beforeNextLoadCompletes;

  @override
  Future<void> configureAudioSession() async {}

  @override
  Future<void> load(MemoryMusicTrack track) async {
    loadAttempts++;
    attemptedTracks.add(track);
    if (failedTrackIDs.contains(track.id)) {
      throw StateError("load failed");
    }
    loadedTracks.add(track);
    final beforeCompleting = beforeNextLoadCompletes;
    beforeNextLoadCompletes = null;
    await beforeCompleting?.call();
  }

  @override
  Future<void> setLooping() async {
    looping = true;
  }

  @override
  Future<void> play() async {
    playAttempts++;
    playing = true;
  }

  @override
  Future<void> playImmediately() async {
    playAttempts++;
    playedImmediately = true;
    playing = true;
  }

  @override
  Future<void> pause() async {
    playing = false;
  }

  @override
  Future<void> pauseImmediately() async {
    pausedImmediately = true;
    playing = false;
  }

  @override
  Future<void> dispose() async {}
}
