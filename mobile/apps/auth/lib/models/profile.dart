enum ProfileKind { online, offline }

// A vault the user can switch to. [scope] is the prefix applied to this
// account's preference and secure storage keys, and to its database filenames.
// The account that predates multi-account support uses an empty scope.
class Profile {
  final String scope;
  final ProfileKind kind;
  final int? userID;
  final String? email;
  final String? label;

  const Profile({
    required this.scope,
    required this.kind,
    this.userID,
    this.email,
    this.label,
  });

  bool get isOffline => kind == ProfileKind.offline;

  // [offlineFallback] is passed in so this stays free of l10n.
  String displayName(String offlineFallback) {
    final named = label?.trim();
    if (named != null && named.isNotEmpty) return named;
    return email ?? offlineFallback;
  }

  Map<String, dynamic> toMap() {
    return {
      'scope': scope,
      'kind': kind.name,
      'userID': userID,
      'email': email,
      'label': label,
    };
  }

  static Profile fromMap(Map<String, dynamic> map) {
    return Profile(
      scope: map['scope'] as String,
      kind: ProfileKind.values.firstWhere(
        (k) => k.name == map['kind'],
        orElse: () => ProfileKind.online,
      ),
      userID: map['userID'] as int?,
      email: map['email'] as String?,
      label: map['label'] as String?,
    );
  }

  @override
  String toString() => "Profile(scope: '$scope', kind: ${kind.name})";
}
