import 'package:ente_frb/accounts.dart';

export 'package:ente_frb/accounts.dart'
    show
        AccountsClient,
        AccountsClientConfig,
        AccountsError,
        AccountsError_Network,
        AccountsError_KeyDerivation,
        AccountsError_IncorrectPassword,
        AccountsError_IncorrectTotp,
        AccountsError_SrpNotConfigured,
        AccountsError_SessionExpired,
        AuthResponse,
        SignupKeys,
        SrpAttributes,
        TwoFactorAuthorizationResponse,
        TwoFactorRecoveryResponse,
        TwoFactorType;

typedef CreateAccountsClient =
    AccountsClient Function({required AccountsClientConfig config});

extension AuthResponseMap on AuthResponse {
  Map<String, dynamic> toMap() => {
    'id': id.toInt(),
    'keyAttributes': keyAttributes?.toMap(),
    'encryptedToken': encryptedToken,
    'token': token,
    'twoFactorSessionID': twoFactorSessionId,
    'twoFactorSessionIDV2': twoFactorSessionIdV2,
    'passkeySessionID': passkeySessionId,
    'accountsUrl': accountsUrl,
  };
}

extension TwoFactorAuthorizationResponseMap on TwoFactorAuthorizationResponse {
  Map<String, dynamic> toMap() => {
    'id': id.toInt(),
    'encryptedToken': encryptedToken,
    'keyAttributes': keyAttributes.toMap(),
  };
}

extension AccountsKeyAttributesMap on KeyAttributes {
  Map<String, dynamic> toMap() => {
    'kekSalt': kekSalt,
    'encryptedKey': encryptedKey,
    'keyDecryptionNonce': keyDecryptionNonce,
    'publicKey': publicKey,
    'encryptedSecretKey': encryptedSecretKey,
    'secretKeyDecryptionNonce': secretKeyDecryptionNonce,
    'memLimit': memLimit.toInt(),
    'opsLimit': opsLimit,
    'masterKeyEncryptedWithRecoveryKey': masterKeyEncryptedWithRecoveryKey,
    'masterKeyDecryptionNonce': masterKeyDecryptionNonce,
    'recoveryKeyEncryptedWithMasterKey': recoveryKeyEncryptedWithMasterKey,
    'recoveryKeyDecryptionNonce': recoveryKeyDecryptionNonce,
  };
}

KeyAttributes accountsKeyAttributes(Map<String, dynamic> value) =>
    KeyAttributes(
      kekSalt: value['kekSalt'] as String,
      encryptedKey: value['encryptedKey'] as String,
      keyDecryptionNonce: value['keyDecryptionNonce'] as String,
      publicKey: value['publicKey'] as String,
      encryptedSecretKey: value['encryptedSecretKey'] as String,
      secretKeyDecryptionNonce: value['secretKeyDecryptionNonce'] as String,
      memLimit: BigInt.from(value['memLimit'] as int),
      opsLimit: value['opsLimit'] as int,
      masterKeyEncryptedWithRecoveryKey:
          value['masterKeyEncryptedWithRecoveryKey'] as String?,
      masterKeyDecryptionNonce: value['masterKeyDecryptionNonce'] as String?,
      recoveryKeyEncryptedWithMasterKey:
          value['recoveryKeyEncryptedWithMasterKey'] as String?,
      recoveryKeyDecryptionNonce:
          value['recoveryKeyDecryptionNonce'] as String?,
    );
