import 'dart:convert';
import 'dart:typed_data';

import 'package:ente_auth/models/code.dart';
import 'package:pointycastle/export.dart';

/// Parses and decrypts Open Authenticator `.bak` backups.
///
/// The backup is a JSON object containing an Argon2id-derived, AES-256-GCM
/// encrypted payload:
///
/// * key: Argon2id (v0x13) over the backup password and the base64 `salt`,
///   with `iterations = 3`, `lanes = 8`, `memory = 4096 KiB`, 32-byte output;
/// * password check: `base64(HMAC-SHA256(key, password))` stored as
///   `passwordSignature`;
/// * each encrypted field is `nonce(12) || ciphertext || tag(16)`, no AAD.
///
/// This file intentionally has no Flutter/UI dependency so it can run inside a
/// background isolate and be unit tested on its own.
///
/// See `OPEN_AUTHENTICATOR_IMPORT_PLAN.md` for the full details.

/// Argon2id parameters used by Open Authenticator (see `bin/generate.dart`).
const int _argon2Iterations = 3;
const int _argon2MemoryKib = 4096; // memorySize = 1 << 12
const int _argon2Lanes = 8; // parallelism
const int _keyLength = 32;

/// Encrypted fields are `nonce || ciphertext || tag`.
const int _nonceLength = 12;
const int _tagLengthBytes = 16;
const int _tagLengthBits = _tagLengthBytes * 8;

/// SHA-256 block size, required by [HMac].
const int _sha256BlockSize = 64;
const int _sha256DigestLength = 32;
const int _backupSaltLength = 32;

const int _minOtpDigits = 1;
const int _maxOtpDigits = 10;

// Backup JSON keys. The same keys are reused for the decrypted entry payload
// that is passed back across the isolate boundary.
const String _saltKey = 'salt';
const String _passwordSignatureKey = 'passwordSignature';
const String _totpsKey = 'totps';
const String _uuidKey = 'uuid';
const String _secretKey = 'secret';
const String _labelKey = 'label';
const String _issuerKey = 'issuer';
const String _encryptionSaltKey = 'encryptionSalt';
const String _algorithmKey = 'algorithm';
const String _digitsKey = 'digits';
const String _validityKey = 'validity';

/// Thrown when the imported file is not a well-formed Open Authenticator backup.
class InvalidOpenAuthenticatorBackupException implements Exception {
  const InvalidOpenAuthenticatorBackupException();

  @override
  String toString() => 'Invalid Open Authenticator backup';
}

/// Thrown when the provided backup password is wrong.
class IncorrectOpenAuthenticatorPasswordException implements Exception {
  const IncorrectOpenAuthenticatorPasswordException();

  @override
  String toString() => 'Incorrect password';
}

/// Thrown when a single backup entry cannot be decrypted.
///
/// Carries the raw entry so the UI can show it to the user.
class OpenAuthenticatorEntryParseException implements Exception {
  final Object? entry;
  final Object error;

  OpenAuthenticatorEntryParseException({
    required this.entry,
    required this.error,
  });

  @override
  String toString() => 'Could not parse Open Authenticator entry: $error';
}

/// Decodes and validates the top-level shape of an Open Authenticator backup.
///
/// Throws [InvalidOpenAuthenticatorBackupException] when the content is not a
/// JSON object with the expected keys.
Map<String, dynamic> decodeOpenAuthenticatorBackup(String jsonString) {
  final Object? decoded;
  try {
    decoded = jsonDecode(jsonString);
  } on FormatException {
    throw const InvalidOpenAuthenticatorBackupException();
  }
  if (decoded is! Map) {
    throw const InvalidOpenAuthenticatorBackupException();
  }

  final Map<String, dynamic> backup = Map<String, dynamic>.from(decoded);
  if (backup[_saltKey] is! String ||
      backup[_passwordSignatureKey] is! String ||
      backup[_totpsKey] is! List) {
    throw const InvalidOpenAuthenticatorBackupException();
  }

  try {
    final salt = base64Decode(backup[_saltKey] as String);
    final signature = base64Decode(backup[_passwordSignatureKey] as String);
    if (salt.length != _backupSaltLength ||
        signature.length != _sha256DigestLength) {
      throw const InvalidOpenAuthenticatorBackupException();
    }
  } on FormatException {
    throw const InvalidOpenAuthenticatorBackupException();
  }

  return backup;
}

/// Decrypts every entry of an already decoded [backup].
///
/// Returns a serializable list of plain maps, so this can be executed inside a
/// background isolate. Throws [IncorrectOpenAuthenticatorPasswordException]
/// when the password signature does not match, and
/// [OpenAuthenticatorEntryParseException] when a single entry cannot be read.
List<Map<String, Object?>> decryptOpenAuthenticatorBackup(
  Map<String, dynamic> backup, {
  required String password,
}) {
  final Uint8List salt;
  try {
    salt = base64Decode(backup[_saltKey] as String);
  } on FormatException {
    throw const InvalidOpenAuthenticatorBackupException();
  }

  final key = _deriveKey(password, salt);
  if (!_verifyPassword(
    key,
    password,
    backup[_passwordSignatureKey] as String,
  )) {
    throw const IncorrectOpenAuthenticatorPasswordException();
  }

  final entries = backup[_totpsKey] as List;
  return [
    for (final entry in entries) _decryptEntry(key, salt, password, entry),
  ];
}

/// Builds [Code]s from the decrypted entries produced by
/// [decryptOpenAuthenticatorBackup].
///
/// The otpauth URI is built here (instead of using the UI-layer
/// `buildImportOtpUri`) so that this parser stays independent from Flutter and
/// remains unit testable. [Code.fromOTPAuthUrl] still performs the actual
/// parsing and normalization.
List<Code> parseOpenAuthenticatorEntries(List<Map<String, Object?>> entries) {
  return [for (final entry in entries) _toCode(entry)];
}

Uint8List _deriveKey(String password, Uint8List salt) {
  final generator = Argon2BytesGenerator()
    ..init(
      Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        salt,
        desiredKeyLength: _keyLength,
        iterations: _argon2Iterations,
        memory: _argon2MemoryKib,
        lanes: _argon2Lanes,
        version: Argon2Parameters.ARGON2_VERSION_13,
      ),
    );
  return generator.process(Uint8List.fromList(utf8.encode(password)));
}

bool _verifyPassword(Uint8List key, String password, String signature) {
  final mac = HMac(SHA256Digest(), _sha256BlockSize)..init(KeyParameter(key));
  final digest = mac.process(Uint8List.fromList(utf8.encode(password)));
  return base64Encode(digest) == signature;
}

Map<String, Object?> _decryptEntry(
  Uint8List backupKey,
  Uint8List backupSalt,
  String password,
  Object? entry,
) {
  if (entry is! Map) {
    throw OpenAuthenticatorEntryParseException(
      entry: entry,
      error: 'entry is not a JSON object',
    );
  }
  final entryMap = Map<String, dynamic>.from(entry);

  final secretBytes = _tryToBytes(entryMap[_secretKey]);
  if (secretBytes == null) {
    throw OpenAuthenticatorEntryParseException(
      entry: entry,
      error: 'missing or malformed secret',
    );
  }

  // Entries normally share the backup salt. Fall back to the entry's own
  // encryptionSalt for backups whose entries kept an older one.
  var key = backupKey;
  var secret = _decryptField(key, secretBytes);
  if (secret == null) {
    final entrySalt = _tryToBytes(entryMap[_encryptionSaltKey]);
    if (entrySalt != null && !_sameBytes(entrySalt, backupSalt)) {
      key = _deriveKey(password, entrySalt);
      secret = _decryptField(key, secretBytes);
    }
  }
  if (secret == null) {
    throw OpenAuthenticatorEntryParseException(
      entry: entry,
      error: 'could not decrypt secret',
    );
  }

  final String? label;
  final String? issuer;
  final int? digits;
  try {
    label = _decryptOptionalField(key, entryMap, fieldName: _labelKey);
    issuer = _decryptOptionalField(key, entryMap, fieldName: _issuerKey);
    digits = _normalizeDigits(
      entryMap[_digitsKey],
      present: entryMap.containsKey(_digitsKey),
    );
  } on Object catch (error) {
    throw OpenAuthenticatorEntryParseException(entry: entry, error: error);
  }

  return {
    _uuidKey: entryMap[_uuidKey] is String ? entryMap[_uuidKey] : null,
    _secretKey: secret,
    _labelKey: label,
    _issuerKey: issuer,
    _algorithmKey: entryMap[_algorithmKey] is String
        ? entryMap[_algorithmKey]
        : null,
    if (digits != null) _digitsKey: digits,
    _validityKey: entryMap[_validityKey] is int ? entryMap[_validityKey] : null,
  };
}

String? _decryptOptionalField(
  Uint8List key,
  Map<String, dynamic> entry, {
  required String fieldName,
}) {
  if (!entry.containsKey(fieldName)) return null;

  final bytes = _tryToBytes(entry[fieldName]);
  if (bytes == null) {
    throw FormatException('malformed encrypted field: $fieldName');
  }

  final decrypted = _decryptField(key, bytes);
  if (decrypted == null) {
    throw FormatException('could not decrypt field: $fieldName');
  }
  return decrypted;
}

/// Decrypts a single `nonce(12) || ciphertext || tag(16)` field.
///
/// Returns `null` when the data is malformed or the authentication tag does
/// not verify (which also signals a wrong key).
String? _decryptField(Uint8List key, Uint8List data) {
  if (data.length < _nonceLength + _tagLengthBytes) {
    return null;
  }
  final nonce = data.sublist(0, _nonceLength);
  final cipherText = data.sublist(_nonceLength); // ciphertext + tag
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(KeyParameter(key), _tagLengthBits, nonce, Uint8List(0)),
    );
  try {
    return utf8.decode(cipher.process(cipherText));
  } on InvalidCipherTextException {
    return null;
  } on FormatException {
    return null;
  }
}

Code _toCode(Map<String, Object?> entry) {
  final secret = entry[_secretKey] as String;
  final label = entry[_labelKey] as String?;
  final issuer = _nonEmpty(entry[_issuerKey] as String?);
  final account = (label != null && label.isNotEmpty)
      ? label
      : (_nonEmpty(entry[_uuidKey] as String?) ?? '');

  final encodedIssuer = Uri.encodeComponent(issuer ?? '');
  final encodedAccount = Uri.encodeComponent(account);
  // Keep an explicit empty issuer separator. Code._getAccount uses the first
  // colon in the path as the issuer/account boundary, so omitting it would
  // truncate issuer-less labels that contain a colon.
  final path = issuer == null
      ? ':$encodedAccount'
      : '$encodedIssuer:$encodedAccount';

  final buffer = StringBuffer(
    'otpauth://totp/$path?secret=${Uri.encodeComponent(secret)}'
    '&issuer=$encodedIssuer',
  );
  final algorithm = _normalizeAlgorithm(entry[_algorithmKey]);
  if (algorithm != null) {
    buffer.write('&algorithm=$algorithm');
  }
  final digits = _normalizeDigits(
    entry[_digitsKey],
    present: entry.containsKey(_digitsKey),
  );
  if (digits != null) {
    buffer.write('&digits=$digits');
  }
  final period = _normalizePeriod(entry[_validityKey]);
  if (period != null) {
    buffer.write('&period=$period');
  }
  return Code.fromOTPAuthUrl(buffer.toString());
}

Uint8List? _tryToBytes(Object? value) {
  if (value is! List) {
    return null;
  }
  final bytes = Uint8List(value.length);
  for (var i = 0; i < value.length; i++) {
    final byte = value[i];
    if (byte is! int || byte < 0 || byte > 255) {
      return null;
    }
    bytes[i] = byte;
  }
  return bytes;
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

String? _normalizeAlgorithm(Object? value) {
  if (value is! String) {
    return null;
  }
  final normalized = value.toLowerCase();
  if (normalized == 'sha1' ||
      normalized == 'sha256' ||
      normalized == 'sha512') {
    return normalized.toUpperCase();
  }
  return null;
}

int? _normalizeDigits(Object? value, {required bool present}) {
  if (!present) return null;
  if (value is! int || value < _minOtpDigits || value > _maxOtpDigits) {
    throw FormatException('Invalid OTP digits: $value');
  }
  return value;
}

int? _normalizePeriod(Object? value) {
  if (value is! int || value <= 0) {
    return null;
  }
  return value;
}

String? _nonEmpty(String? value) {
  return (value == null || value.isEmpty) ? null : value;
}
