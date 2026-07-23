import 'dart:convert';

import 'package:ente_auth/models/code.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:pointycastle/export.dart';

const _protonExportVersion = 1;
const _protonExportNonceLength = 12;
const _protonExportMacSizeBits = 128;
const _protonExportSaltLength = 16;
const _protonExportPasswordKeyLength = 32;
const _protonExportAad = 'proton.authenticator.export.v1';

final _logger = Logger('ProtonImportParser');

class IncorrectProtonExportPasswordException implements Exception {
  const IncorrectProtonExportPasswordException();

  @override
  String toString() => 'Incorrect password';
}

Map<String, dynamic> decodeProtonExportJson(String jsonString) {
  final decodedJson = jsonDecode(jsonString);
  if (decodedJson is! Map) {
    throw const FormatException('Invalid Proton export');
  }

  final exportJson = Map<String, dynamic>.from(decodedJson);
  _validateProtonExportVersion(exportJson);
  return exportJson;
}

bool isEncryptedProtonExport(Map<String, dynamic> decodedJson) {
  return decodedJson['salt'] != null &&
      decodedJson['content'] != null &&
      decodedJson['entries'] == null;
}

List<Code> parseProtonExport(Map<String, dynamic> decodedJson) {
  if (isEncryptedProtonExport(decodedJson)) {
    throw const FormatException('Password protected Proton export');
  }

  final version = decodedJson['version'];
  final entries = decodedJson['entries'];
  if (version != _protonExportVersion || entries is! List) {
    throw const FormatException('Invalid Proton export');
  }

  final parsedCodes = <Code>[];
  for (final entry in entries) {
    if (entry is! Map) {
      continue;
    }

    try {
      final entryMap = Map<String, dynamic>.from(entry);
      final content = entryMap['content'];
      if (content is! Map) {
        continue;
      }

      final contentMap = Map<String, dynamic>.from(content);
      final entryType = contentMap['entry_type'] as String?;

      Code code;
      switch (entryType) {
        case 'Steam':
          final steamUri = contentMap['uri'] as String?;
          if (steamUri == null || !steamUri.startsWith('steam://')) {
            continue;
          }

          final name = (contentMap['name'] as String?)?.trim();
          code = Code.fromAccountAndSecret(
            Type.steam,
            '',
            name == null || name.isEmpty ? 'Steam' : name,
            steamUri.substring('steam://'.length),
            null,
            Code.steamDigits,
          );
          break;
        case 'Totp':
          final otpUri = contentMap['uri'] as String?;
          if (otpUri == null || !otpUri.startsWith('otpauth://')) {
            continue;
          }
          code = _parseProtonTotpCode(otpUri);
          break;
        default:
          _logger.warning('Unsupported Proton entry type: $entryType');
          continue;
      }

      final note = entryMap['note'] as String?;
      if (note != null && note.isNotEmpty) {
        code = code.copyWith(display: code.display.copyWith(note: note));
      }

      parsedCodes.add(_serializeImportedCode(code));
    } catch (e, s) {
      _logger.warning('Failed to parse Proton export entry', e, s);
    }
  }

  return parsedCodes;
}

String decryptProtonExport(
  Map<String, dynamic> decodedJson, {
  required String password,
}) {
  _validateProtonExportVersion(decodedJson);
  if (!isEncryptedProtonExport(decodedJson)) {
    throw const FormatException('Invalid Proton export');
  }

  final saltBase64 = decodedJson['salt'];
  final contentBase64 = decodedJson['content'];
  if (saltBase64 is! String || contentBase64 is! String) {
    throw const FormatException('Invalid Proton export');
  }

  final salt = base64Decode(saltBase64);
  if (salt.length != _protonExportSaltLength) {
    throw const FormatException('Invalid Proton export salt');
  }

  final encryptedBytes = base64Decode(contentBase64);
  if (encryptedBytes.length <= _protonExportNonceLength) {
    throw const FormatException('Invalid Proton export content');
  }

  final key = _deriveProtonPasswordKey(password, Uint8List.fromList(salt));
  final nonce = encryptedBytes.sublist(0, _protonExportNonceLength);
  final cipherText = encryptedBytes.sublist(_protonExportNonceLength);

  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(
        KeyParameter(key),
        _protonExportMacSizeBits,
        nonce,
        Uint8List.fromList(utf8.encode(_protonExportAad)),
      ),
    );

  late final Uint8List decryptedBytes;
  try {
    decryptedBytes = cipher.process(cipherText);
  } on InvalidCipherTextException {
    throw const IncorrectProtonExportPasswordException();
  }
  return utf8.decode(decryptedBytes);
}

@visibleForTesting
Uint8List deriveProtonPasswordKeyForTesting(String password, Uint8List salt) {
  return _deriveProtonPasswordKey(password, salt);
}

@visibleForTesting
String get protonExportAadForTesting => _protonExportAad;

Uint8List _deriveProtonPasswordKey(String password, Uint8List salt) {
  final generator = Argon2BytesGenerator()
    ..init(
      Argon2Parameters(
        Argon2Parameters.ARGON2_id,
        salt,
        desiredKeyLength: _protonExportPasswordKeyLength,
        iterations: 2,
        memory: 19 * 1024,
        lanes: 1,
        version: Argon2Parameters.ARGON2_VERSION_13,
      ),
    );

  return generator.process(Uint8List.fromList(utf8.encode(password)));
}

void _validateProtonExportVersion(Map<String, dynamic> decodedJson) {
  if (decodedJson['version'] != _protonExportVersion) {
    throw const FormatException('Invalid Proton export');
  }
}

Code _parseProtonTotpCode(String otpUri) {
  final parsedCode = Code.fromOTPAuthUrl(otpUri);
  final encodedIssuer = Uri.encodeComponent(parsedCode.issuer);
  final encodedAccount = Uri.encodeComponent(parsedCode.account);
  final otpUrl =
      'otpauth://totp/$encodedIssuer:$encodedAccount?secret=${parsedCode.secret}'
      '&issuer=$encodedIssuer'
      '&algorithm=${parsedCode.algorithm.name.toUpperCase()}'
      '&digits=${parsedCode.digits}'
      '&period=${parsedCode.period}';
  return _serializeImportedCode(Code.fromOTPAuthUrl(otpUrl));
}

Code _serializeImportedCode(Code code) {
  final serializedRawData = jsonDecode(code.toOTPAuthUrlFormat()) as String;
  return Code.fromOTPAuthUrl(serializedRawData);
}
