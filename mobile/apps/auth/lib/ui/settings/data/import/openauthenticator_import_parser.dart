import 'dart:convert';
import 'dart:typed_data';

import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:pointycastle/export.dart';

class IncorrectOpenAuthenticatorPasswordException implements Exception {
  const IncorrectOpenAuthenticatorPasswordException();
}

Map<String, dynamic> decodeOpenAuthenticatorBackup(String jsonString) {
  final backup = jsonDecode(jsonString);
  if (backup is! Map<String, dynamic> ||
      backup['salt'] is! String ||
      backup['passwordSignature'] is! String ||
      backup['totps'] is! List) {
    throw const FormatException('Invalid Open Authenticator backup');
  }
  if (base64Decode(backup['salt'] as String).length != 32 ||
      base64Decode(backup['passwordSignature'] as String).length != 32) {
    throw const FormatException('Invalid Open Authenticator salt or signature');
  }
  return backup;
}

List<Code> decryptOpenAuthenticatorBackup(
  Map<String, dynamic> backup, {
  required String password,
}) {
  final salt = base64Decode(backup['salt'] as String);
  final key = _deriveKey(password, salt);
  final mac = HMac(SHA256Digest(), 64)..init(KeyParameter(key));
  final signature = mac.process(Uint8List.fromList(utf8.encode(password)));
  if (base64Encode(signature) != backup['passwordSignature']) {
    throw const IncorrectOpenAuthenticatorPasswordException();
  }

  final codes = <Code>[];
  for (final entry in backup['totps'] as List) {
    try {
      codes.add(_decryptEntry(entry as Map<String, dynamic>, key));
    } catch (error) {
      throwImportEntryParseError(entry, error);
    }
  }
  return codes;
}

Code _decryptEntry(Map<String, dynamic> entry, Uint8List key) {
  final secret = _decryptField(key, _bytes(entry['secret']));
  final label = entry.containsKey('label')
      ? _decryptField(key, _bytes(entry['label']))
      : '';
  final issuer = entry.containsKey('issuer')
      ? _decryptField(key, _bytes(entry['issuer']))
      : '';
  final account = label.isNotEmpty ? label : (entry['uuid'] as String? ?? '');
  final digits = entry.containsKey('digits')
      ? entry['digits']
      : Code.defaultDigits;
  if (digits is! int || digits < 1 || digits > 10) {
    throw FormatException('Invalid OTP digits: $digits');
  }
  final algorithm = switch (entry['algorithm']) {
    final String value => value.toLowerCase(),
    _ => '',
  };

  return Code.fromOTPAuthUrl(
    buildImportOtpUri(
      kind: 'totp',
      issuer: Uri.encodeComponent(issuer),
      account: Uri.encodeComponent(account),
      secret: Uri.encodeComponent(secret),
      algorithm: const ['sha1', 'sha256', 'sha512'].contains(algorithm)
          ? algorithm
          : 'sha1',
      digits: digits,
      period: entry['validity'] is int ? entry['validity'] : null,
    ),
  );
}

Uint8List _deriveKey(String password, Uint8List salt) {
  final generator = Argon2BytesGenerator()
    ..init(
      Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        salt,
        desiredKeyLength: 32,
        iterations: 3,
        memory: 4096,
        lanes: 8,
        version: Argon2Parameters.ARGON2_VERSION_13,
      ),
    );
  return generator.process(Uint8List.fromList(utf8.encode(password)));
}

String _decryptField(Uint8List key, Uint8List data) {
  const nonceLength = 12;
  const tagLength = 16;
  if (data.length < nonceLength + tagLength) {
    throw const FormatException('Truncated encrypted field');
  }
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(
        KeyParameter(key),
        tagLength * 8,
        data.sublist(0, nonceLength),
        Uint8List(0),
      ),
    );
  return utf8.decode(cipher.process(data.sublist(nonceLength)));
}

Uint8List _bytes(Object? value) {
  if (value is! List ||
      value.any((byte) => byte is! int || byte < 0 || byte > 255)) {
    throw const FormatException('Invalid byte array');
  }
  return Uint8List.fromList(value.cast<int>());
}
