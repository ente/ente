class MemoryMusicTrack {
  final String id;
  final String assetPath;
  final String? title;
  final String? artist;

  const MemoryMusicTrack({
    required this.id,
    required this.assetPath,
    this.title,
    this.artist,
  });
}
