/*
Version: 1.0
KDF Algo: ARGON2ID
Decrypted Data Format: It contains code.rawData [1] separated by new line.
[1] otpauth://totp/provider.com:you@email.com?secret=YOUR_SECRET
*/

class EnteAuthExport {
  final int version;
  final KDFParams kdfParams;
  final String encryptedData;
  final String encryptionNonce;

  EnteAuthExport({
    required this.version,
    required this.kdfParams,
    required this.encryptedData,
    required this.encryptionNonce,
  });

  Map<String, dynamic> toJson() => {
    'version': version,
    'kdfParams': kdfParams.toJson(),
    'encryptedData': encryptedData,
    'encryptionNonce': encryptionNonce,
  };

  static EnteAuthExport fromJson(Map<String, dynamic> json) => EnteAuthExport(
    version: json['version'],
    kdfParams: KDFParams.fromJson(json['kdfParams']),
    encryptedData: json['encryptedData'],
    encryptionNonce: json['encryptionNonce'],
  );
}

class KDFParams {
  final int memLimit;
  final int opsLimit;
  final String salt;

  KDFParams({
    required this.memLimit,
    required this.opsLimit,
    required this.salt,
  });

  Map<String, dynamic> toJson() => {
    'memLimit': memLimit,
    'opsLimit': opsLimit,
    'salt': salt,
  };

  static KDFParams fromJson(Map<String, dynamic> json) => KDFParams(
    memLimit: json['memLimit'],
    opsLimit: json['opsLimit'],
    salt: json['salt'],
  );
}
