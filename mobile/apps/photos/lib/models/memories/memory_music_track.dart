class MemoryMusicTrack {
  final String id;
  final String url;
  final String cacheFileName;
  final String? title;
  final String? artist;

  const MemoryMusicTrack({
    required this.id,
    required this.url,
    required this.cacheFileName,
    this.title,
    this.artist,
  });
}
