class LibrarySharingRecipient {
  const LibrarySharingRecipient({
    required this.userID,
    required this.email,
    this.displayName,
  });

  final int userID;
  final String email;
  final String? displayName;

  String get label {
    final name = displayName?.trim();
    return name == null || name.isEmpty ? email : name;
  }
}
