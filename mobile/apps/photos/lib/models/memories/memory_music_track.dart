class MemoryMusicTrack {
  final String id;
  final String url;
  final String? title;
  final String? artist;

  const MemoryMusicTrack({
    required this.id,
    required this.url,
    this.title,
    this.artist,
  });
}
