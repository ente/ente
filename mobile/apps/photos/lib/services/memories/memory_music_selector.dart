import "dart:convert";

import "package:crypto/crypto.dart";
import "package:photos/models/memories/memory_music_track.dart";

Map<String, MemoryMusicTrack> assignMemoryMusicTracks({
  required Iterable<String> memoryIDs,
  required List<MemoryMusicTrack> tracks,
}) {
  final assignments = <String, MemoryMusicTrack>{};
  String? previousTrackID;
  for (final memoryID in memoryIDs) {
    var trackIndex = _stableTrackIndex(memoryID, tracks.length);
    if (tracks.length > 1 && tracks[trackIndex].id == previousTrackID) {
      trackIndex = (trackIndex + 1) % tracks.length;
    }
    final track = tracks[trackIndex];
    assignments[memoryID] = track;
    previousTrackID = track.id;
  }
  return assignments;
}

int _stableTrackIndex(String memoryID, int trackCount) {
  return sha256.convert(utf8.encode(memoryID)).bytes.first % trackCount;
}
