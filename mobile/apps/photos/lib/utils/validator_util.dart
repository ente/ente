import 'dart:convert';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:photos/gateways/users/models/key_attributes.dart';

Logger _logger = Logger("Validator");

void validatePreVerificationStateCheck(
  KeyAttributes? keyAttr,
  String? password,
  String? encryptedToken,
) {
  nullOrEmptyArgCheck(encryptedToken, "encryptedToken");
  nullOrEmptyArgCheck(password, "userPassword");
  if (keyAttr == null) {
    throw ArgumentError("key Attributes can not be null");
  }
  nullOrEmptyArgCheck(keyAttr.kekSalt, "keySalt");
  nullOrEmptyArgCheck(keyAttr.encryptedKey, "encryptedKey");
  nullOrEmptyArgCheck(keyAttr.keyDecryptionNonce, "keyDecryptionNonce");
  nullOrEmptyArgCheck(keyAttr.encryptedSecretKey, "encryptedSecretKey");
  nullOrEmptyArgCheck(
    keyAttr.secretKeyDecryptionNonce,
    "secretKeyDecryptionNonce",
  );
  nullOrEmptyArgCheck(keyAttr.publicKey, "publicKey");
  if (keyAttr.memLimit == null || keyAttr.opsLimit == null) {
    throw ArgumentError("Key mem/OpsLimit can not be null");
  }
  if (keyAttr.memLimit! <= 0 || keyAttr.opsLimit! <= 0) {
    throw ArgumentError("Key mem/OpsLimit can not be <0");
  }
  try {
    final Uint8List passwordL = utf8.encode(password!);
    try {
      utf8.decode(passwordL);
    } catch (e) {
      _logger.severe("CRITICAL: password decode failed");
      rethrow;
    }
  } catch (e) {
    _logger.severe('CRITICAL: password encode failed');
    rethrow;
  }
}

void nullOrEmptyArgCheck(String? value, String name) {
  if (value == null || value.isEmpty) {
    throw ArgumentError("Critical: $name is nullOrEmpty");
  }
}
