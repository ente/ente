import 'package:ente_base/models/key_attributes.dart';
import 'package:ente_frb/legacy.dart';
import 'package:locker/src/rust/api/legacy.dart' as rust;
import 'package:locker/src/rust/third_party/ente_frb_lib/session.dart';

export 'package:locker/src/rust/api/legacy.dart'
    show
        blockKitRecovery,
        deleteKit,
        downloadKitShares,
        kits,
        updateKitRecoveryNotice;

Future<LegacyKitCreateResult> createKit({
  required Session session,
  required KeyAttributes currentUserKeyAttrs,
  required List<String> partNames,
  required int noticePeriodInHours,
}) => rust.createKit(
  session: session,
  currentUserKeyAttrs: _toRustKeyAttributes(currentUserKeyAttrs),
  partNames: partNames,
  noticePeriodInHours: noticePeriodInHours,
);

rust.AccountKeyAttributes _toRustKeyAttributes(KeyAttributes attributes) {
  return rust.AccountKeyAttributes(
    kekSalt: attributes.kekSalt,
    encryptedKey: attributes.encryptedKey,
    keyDecryptionNonce: attributes.keyDecryptionNonce,
    publicKey: attributes.publicKey,
    encryptedSecretKey: attributes.encryptedSecretKey,
    secretKeyDecryptionNonce: attributes.secretKeyDecryptionNonce,
    memLimit: attributes.memLimit,
    opsLimit: attributes.opsLimit,
    masterKeyEncryptedWithRecoveryKey:
        attributes.masterKeyEncryptedWithRecoveryKey,
    masterKeyDecryptionNonce: attributes.masterKeyDecryptionNonce,
    recoveryKeyEncryptedWithMasterKey:
        attributes.recoveryKeyEncryptedWithMasterKey,
    recoveryKeyDecryptionNonce: attributes.recoveryKeyDecryptionNonce,
  );
}
