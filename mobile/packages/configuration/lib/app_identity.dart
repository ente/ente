class EnteAppIdentity {
  const EnteAppIdentity({
    required this.app,
    required this.clientPackageName,
    required this.passkeyRedirectUrl,
    required this.referralSourcePrefix,
  });

  final String app;
  final String clientPackageName;
  final String passkeyRedirectUrl;
  final String referralSourcePrefix;
}
