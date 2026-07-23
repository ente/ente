class PublicURL {
  String url;
  int deviceLimit;
  int validTill;
  bool enableDownload;
  bool enableCollect;
  bool passwordEnabled;
  bool enableJoin;
  bool enableComment;
  String? nonce;
  int? opsLimit;
  int? memLimit;

  PublicURL({
    required this.url,
    required this.deviceLimit,
    required this.validTill,
    this.enableDownload = true,
    this.passwordEnabled = false,
    this.enableCollect = false,
    this.enableJoin = true,
    this.enableComment = false,
    this.nonce,
    this.opsLimit,
    this.memLimit,
  });

  Map<String, dynamic> toMap() {
    return {
      'url': url,
      'deviceLimit': deviceLimit,
      'validTill': validTill,
      'enableDownload': enableDownload,
      'passwordEnabled': passwordEnabled,
      'enableCollect': enableCollect,
      'nonce': nonce,
      'memLimit': memLimit,
      'opsLimit': opsLimit,
      'enableJoin': enableJoin,
      'enableComment': enableComment,
    };
  }

  bool get hasExpiry => validTill != 0;

  // isExpired indicates whether the link has expired or not
  bool get isExpired =>
      hasExpiry && validTill < DateTime.now().microsecondsSinceEpoch;

  static PublicURL fromMap(Map<String, dynamic> map) {
    return PublicURL(
      url: map['url'],
      deviceLimit: map['deviceLimit'],
      validTill: map['validTill'] ?? 0,
      enableDownload: map['enableDownload'] ?? true,
      passwordEnabled: map['passwordEnabled'] ?? false,
      enableCollect: map['enableCollect'] ?? false,
      nonce: map['nonce'],
      opsLimit: map['opsLimit'],
      memLimit: map['memLimit'],
      enableJoin: map['enableJoin'] ?? true,
      enableComment: map['enableComment'] ?? false,
    );
  }
}
