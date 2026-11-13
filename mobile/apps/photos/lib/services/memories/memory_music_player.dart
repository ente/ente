import "package:photos/models/memories/memory_music_track.dart";

abstract interface class MemoryMusicPlayer {
  Future<void> configureAudioSession();

  Future<void> load(MemoryMusicTrack track);

  Future<void> play();

  Future<void> playImmediately();

  Future<void> pause();

  Future<void> pauseImmediately();

  Future<void> dispose();
}
