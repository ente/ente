class AnonProfile {
  final String anonUserID;
  final int collectionID;
  final String data;
  final int createdAt;
  final int updatedAt;

  AnonProfile({
    required this.anonUserID,
    required this.collectionID,
    required this.data,
    required this.createdAt,
    required this.updatedAt,
  });

  String? get displayName {
    final trimmed = data.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
