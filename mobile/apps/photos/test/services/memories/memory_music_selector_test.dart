import "package:flutter_test/flutter_test.dart";
import "package:photos/models/memories/memory_music_track.dart";
import "package:photos/services/memories/memory_music_selector.dart";

void main() {
  const tracks = <MemoryMusicTrack>[
    MemoryMusicTrack(id: "track-1", assetPath: "assets/track-1.mp3"),
    MemoryMusicTrack(id: "track-2", assetPath: "assets/track-2.mp3"),
    MemoryMusicTrack(id: "track-3", assetPath: "assets/track-3.mp3"),
  ];
  const memoryIDs = <String>["memory-a", "memory-b", "memory-c", "memory-d"];

  test("assigns stable tracks without adjacent repeats", () {
    final assignments = assignMemoryMusicTracks(
      memoryIDs: memoryIDs,
      tracks: tracks,
    );

    expect(memoryIDs.map((memoryID) => assignments[memoryID]!.id), <String>[
      "track-2",
      "track-1",
      "track-2",
      "track-3",
    ]);
  });

  test("one-track list reuses its only track", () {
    final assignments = assignMemoryMusicTracks(
      memoryIDs: memoryIDs,
      tracks: const <MemoryMusicTrack>[
        MemoryMusicTrack(id: "track-1", assetPath: "assets/track-1.mp3"),
      ],
    );

    expect(
      assignments.values.map((track) => track.id),
      everyElement("track-1"),
    );
  });
}
