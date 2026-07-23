// Loaded from assets/discover.json
class Prompt {
  final String id;
  final int position;
  final String query;
  final double minScore;
  final double minSize;
  final String title;
  final bool showVideo;
  final bool recentFirst;

  // fromJson
  Prompt.fromJson(Map<String, dynamic> json)
    : id = json['id'] ?? json['title'],
      query = json['query'] ?? json['prompt'],
      minScore = json['minScore'] ?? json['minimumScore'] ?? 0.2,
      minSize = json['minSize'] ?? json['minimumSize'] ?? 0.0,
      position = json['position'] ?? 0,
      title = json['title'],
      recentFirst = json['recentFirst'] ?? false,
      showVideo = json['showVideo'] ?? true;
}
