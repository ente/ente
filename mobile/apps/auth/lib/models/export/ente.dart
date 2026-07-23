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

  // Named constructor which can be used to specify each field individually
  EnteAuthExport({
    required this.version,
    required this.kdfParams,
    required this.encryptedData,
    required this.encryptionNonce,
  });

  // Convert EnteExport object to JSON
  Map<String, dynamic> toJson() => {
    'version': version,
    'kdfParams': kdfParams.toJson(),
    'encryptedData': encryptedData,
    'encryptionNonce': encryptionNonce,
  };

  // Convert JSON to EnteExport object
  static EnteAuthExport fromJson(Map<String, dynamic> json) => EnteAuthExport(
    version: json['version'],
    kdfParams: KDFParams.fromJson(json['kdfParams']),
    encryptedData: json['encryptedData'],
    encryptionNonce: json['encryptionNonce'],
  );
}

// KDFParams is a class that holds the parameters for the KDF function.
// It is used to derive a key from a password.
class KDFParams {
  final int memLimit;
  final int opsLimit;
  final String salt;

  // Named constructor which can be used to specify each field individually
  KDFParams({
    required this.memLimit,
    required this.opsLimit,
    required this.salt,
  });

  // Convert KDFParams object to JSON
  Map<String, dynamic> toJson() => {
    'memLimit': memLimit,
    'opsLimit': opsLimit,
    'salt': salt,
  };

  // Convert JSON to KDFParams object
  static KDFParams fromJson(Map<String, dynamic> json) => KDFParams(
    memLimit: json['memLimit'],
    opsLimit: json['opsLimit'],
    salt: json['salt'],
  );
}
