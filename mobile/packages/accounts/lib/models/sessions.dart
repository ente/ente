class Sessions {
  final List<Session> sessions;

  Sessions(this.sessions);

  factory Sessions.fromMap(Map<String, dynamic> map) {
    if (map["sessions"] == null) {
      throw Exception('\'map["sessions"]\' must not be null');
    }
    return Sessions(
      List<Session>.from(map['sessions']?.map((x) => Session.fromMap(x))),
    );
  }
}

class Session {
  final String token;
  final bool? isCurrent;
  final int creationTime;
  final String ip;
  final String ua;
  final String prettyUA;
  final int lastUsedTime;

  Session(
    this.token,
    this.isCurrent,
    this.creationTime,
    this.ip,
    this.ua,
    this.prettyUA,
    this.lastUsedTime,
  );

  factory Session.fromMap(Map<String, dynamic> map) {
    return Session(
      map['token'],
      map['isCurrent'],
      map['creationTime'],
      map['ip'],
      map['ua'],
      map['prettyUA'],
      map['lastUsedTime'],
    );
  }

  bool isCurrentSession(String? currentToken) =>
      isCurrent ?? token == currentToken;
}
