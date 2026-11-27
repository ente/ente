class ActiveSession {
  const ActiveSession({
    required this.id,
    required this.isCurrent,
    required this.createdAt,
    required this.lastUsedAt,
    required this.ip,
    required this.userAgent,
    required this.prettyUserAgent,
  });

  final String id;
  final bool isCurrent;
  final int createdAt;
  final int lastUsedAt;
  final String ip;
  final String userAgent;
  final String prettyUserAgent;
}
