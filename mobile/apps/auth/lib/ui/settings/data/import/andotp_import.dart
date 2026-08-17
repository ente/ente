import 'dart:convert';

import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/models/code_display.dart';
import 'package:ente_auth/ui/settings/data/import/import_file_cleanup.dart';
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/progress_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:pointycastle/export.dart';

final _logger = Logger('AndOTPImport');

Future<void> showAndOTPImportInstruction(BuildContext context) async {
  final l10n = context.strings;
  await showFileImportInstruction(
    context: context,
    title: "andOTP",
    body: l10n.importAndOTPGuide,
    actionLabel: l10n.importSelectAppExport(appName: "andOTP"),
    semanticsIdentifier: 'auth_import_instruction_andotp',
    onImport: () => _pickAndOTPFile(context),
  );
}

Future<void> _pickAndOTPFile(BuildContext context) async {
  await pickAndProcessImportFile(
    context: context,
    dialogTitle: context.strings.importSelectAppExport(appName: "andOTP"),
    type: FileType.custom,
    allowedExtensions: ['json', 'aes'],
    showProgressBeforeProcessing: false,
    logger: _logger,
    logMessage: 'Exception while processing andOTP import',
    process: (path, progressDialog) =>
        _processAndOTPFile(context, path, progressDialog),
  );
}

class _DecryptParams {
  final Uint8List fileBytes;
  final String password;

  _DecryptParams({required this.fileBytes, required this.password});
}

Future<int?> _processAndOTPFile(
  BuildContext context,
  String path,
  ProgressDialog dialog,
) async {
  List<dynamic> entries;

  // Valid JSON arrays are plain text; binary files need decryption.
  final Uint8List fileBytes = await readPickedImportFileAsBytes(path);

  try {
    final jsonString = utf8.decode(fileBytes);
    entries = jsonDecode(jsonString) as List<dynamic>;
    await dialog.show();
  } catch (e) {
    if (!context.mounted) return null;
    String? password;
    try {
      password = await promptForImportPassword(
        context,
        title: context.strings.enterPasswordToDecryptAndOTP,
      );
      if (password == null) {
        return null;
      }
      await dialog.show();
      final decryptedContent = await compute(
        _decryptAndOTPBackup,
        _DecryptParams(fileBytes: fileBytes, password: password),
      );
      entries = jsonDecode(decryptedContent) as List<dynamic>;
    } catch (e, s) {
      _logger.warning("Exception while decrypting andOTP backup", e, s);
      await dialog.hide();
      if (password != null) {
        if (!context.mounted) return null;
        await showErrorDialog(
          context,
          context.strings.failedToDecryptAndOTPBackup,
          context.strings.pleaseCheckPasswordAndTryAgain,
        );
      }
      return null;
    }
  }

  final List<Code> parsedCodes = [];

  for (var item in entries) {
    final String type = (item['type'] as String).toUpperCase();
    final String issuer = item['issuer'] ?? '';
    final String label = item['label'] ?? '';
    final String displayName = issuer.isNotEmpty
        ? (label.isNotEmpty ? '$issuer ($label)' : issuer)
        : label;

    if (type != 'TOTP' && type != 'HOTP' && type != 'STEAM') {
      _logger.warning('Skipping unsupported OTP type: $type for $displayName');
      continue;
    }

    try {
      final String secret = item['secret'];
      final String algorithm = item['algorithm'] ?? 'SHA1';
      final int digits = item['digits'] ?? 6;
      final int period = item['period'] ?? 30;
      final int counter = item['counter'] ?? 0;
      final List<dynamic>? tagsList = item['tags'];
      final List<String> tags =
          tagsList?.map((t) => t.toString()).toList() ?? [];

      final String encodedIssuer = Uri.encodeComponent(issuer);
      final String encodedLabel = Uri.encodeComponent(label);

      Code code = Code.fromOTPAuthUrl(
        buildImportOtpUri(
          kind: type,
          issuer: encodedIssuer,
          account: encodedLabel,
          secret: secret,
          algorithm: algorithm,
          digits: digits,
          period: period,
          counter: counter,
        ),
      );
      if (tags.isNotEmpty) {
        code = code.copyWith(display: CodeDisplay(tags: tags));
      }
      parsedCodes.add(code);
    } catch (e, s) {
      _logger.warning('Failed to parse andOTP entry: $displayName', e, s);
      throwImportEntryParseError(item, e);
    }
  }

  return saveImportedCodes(parsedCodes);
}

// Must remain top-level for compute().
String _decryptAndOTPBackup(_DecryptParams params) {
  final Uint8List fileBytes = params.fileBytes;
  final String password = params.password;

  // andOTP encrypted file structure:
  // [iterations: 4 bytes][salt: 12 bytes][IV + ciphertext + auth tag]
  const int intLength = 4;
  const int saltLength = 12;
  const int ivLength = 12;

  if (fileBytes.length < intLength + saltLength + ivLength) {
    throw Exception('Invalid andOTP encrypted file: file too small');
  }

  final ByteData byteData = ByteData.sublistView(fileBytes, 0, intLength);
  final int iterations = byteData.getInt32(0, Endian.big);

  final Uint8List salt = Uint8List.sublistView(
    fileBytes,
    intLength,
    intLength + saltLength,
  );

  final Uint8List encryptedPayload = Uint8List.sublistView(
    fileBytes,
    intLength + saltLength,
  );

  final Uint8List iv = Uint8List.sublistView(encryptedPayload, 0, ivLength);

  final Uint8List ciphertextWithTag = Uint8List.sublistView(
    encryptedPayload,
    ivLength,
  );

  const int keyLength = 32;
  final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA1Digest(), 64));
  pbkdf2.init(Pbkdf2Parameters(salt, iterations, keyLength));

  final Uint8List derivedKey = Uint8List(keyLength);
  pbkdf2.deriveKey(Uint8List.fromList(utf8.encode(password)), 0, derivedKey, 0);

  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(
        KeyParameter(derivedKey),
        128, // auth tag length in bits
        iv,
        Uint8List(0), // no additional authenticated data
      ),
    );

  final Uint8List decryptedBytes = cipher.process(ciphertextWithTag);
  return utf8.decode(decryptedBytes);
}
