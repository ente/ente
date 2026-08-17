import 'dart:typed_data';

typedef AccountKeyProvider = Future<Uint8List> Function();

// accountKey is the existing top-level account key. Contacts uses it only to
// unwrap or create the per-user contact root key.
class ContactsSession {
  final String baseUrl;
  final String authToken;
  final int userId;

  final Uint8List? accountKey;

  final AccountKeyProvider? accountKeyProvider;
  final String? userAgent;
  final String? clientPackage;
  final String? clientVersion;

  ContactsSession({
    required this.baseUrl,
    required this.authToken,
    required this.userId,
    this.accountKey,
    this.accountKeyProvider,
    this.userAgent,
    this.clientPackage,
    this.clientVersion,
  }) : assert(
         accountKey != null || accountKeyProvider != null,
         'ContactsSession requires accountKey or accountKeyProvider',
       );

  Future<Uint8List> resolveAccountKey() async {
    final accountKey = this.accountKey;
    if (accountKey != null) {
      return accountKey;
    }
    final provider = accountKeyProvider;
    if (provider == null) {
      throw StateError(
        'ContactsSession requires accountKey or accountKeyProvider',
      );
    }
    return provider();
  }
}
