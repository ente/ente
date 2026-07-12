import 'dart:async';
import 'dart:convert';

import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/models/code_display.dart';
import 'package:ente_auth/services/authenticator_service.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/ui/components/buttons/button_widget.dart';
import 'package:ente_auth/ui/components/dialog_widget.dart';
import 'package:ente_auth/ui/components/models/button_type.dart';
import 'package:ente_auth/ui/settings/data/import/import_file_cleanup.dart';
import 'package:ente_auth/ui/settings/data/import/import_success.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_ui/components/progress_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:pointycastle/export.dart';

final _logger = Logger('AndOTPImport');

Future<void> showAndOTPImportInstruction(BuildContext context) async {
  final l10n = context.l10n;
  final result = await showDialogWidget(
    context: context,
    title: l10n.importFromApp("andOTP"),
    body: l10n.importAndOTPGuide,
    buttons: [
      ButtonWidget(
        buttonType: ButtonType.primary,
        labelText: l10n.importSelectAppExport("andOTP"),
        isInAlert: true,
        buttonSize: ButtonSize.large,
        buttonAction: ButtonAction.first,
      ),
      ButtonWidget(
        buttonType: ButtonType.secondary,
        labelText: l10n.cancel,
        buttonSize: ButtonSize.large,
        isInAlert: true,
        buttonAction: ButtonAction.second,
      ),
    ],
  );
  if (result?.action != null && result!.action != ButtonAction.cancel) {
    if (!context.mounted) return;
    if (result.action == ButtonAction.first) {
      await _pickAndOTPFile(context);
    }
  }
}

Future<void> _pickAndOTPFile(BuildContext context) async {
  final l10n = context.l10n;
  FilePickerResult? result = await FilePicker.platform.pickFiles(
    dialogTitle: l10n.importSelectAppExport("andOTP"),
    allowMultiple: false,
    type: FileType.custom,
    allowedExtensions: ['json', 'aes'],
  );
  if (result == null) {
    return;
  }
  if (!context.mounted) return;
  final ProgressDialog progressDialog = createProgressDialog(
    context,
    l10n.pleaseWait,
  );

  try {
    if (!context.mounted) return;
    String path = result.files.single.path!;
    final count = await _processAndOTPFile(context, path, progressDialog);
    await progressDialog.hide();
    if (count != null) {
      if (!context.mounted) return;
      await importSuccessDialog(context, count);
    }
  } catch (e, s) {
    _logger.severe('Exception while processing andOTP import', e, s);
    await progressDialog.hide();
    if (!context.mounted) return;
    await showErrorDialog(
      context,
      l10n.sorry,
      "${l10n.importFailureDesc}\n Error: ${e.toString()}",
    );
  }
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

  // Try to detect if file is encrypted or plain text
  // Plain text files are valid JSON arrays, encrypted files are binary
  final Uint8List fileBytes = await readPickedImportFileAsBytes(path);

  try {
    // Try to parse as JSON (plain text format)
    final jsonString = utf8.decode(fileBytes);
    entries = jsonDecode(jsonString) as List<dynamic>;
    await dialog.show();
  } catch (e) {
    if (!context.mounted) return null;
    // If JSON parsing fails, assume it's encrypted
    String? password;
    try {
      await showTextInputDialog(
        context,
        title: context.l10n.enterPasswordToDecryptAndOTP,
        submitButtonLabel: context.l10n.submit,
        isPasswordInput: true,
        onSubmit: (value) async {
          password = value;
        },
      );
      if (password == null) {
        return null;
      }
      await dialog.show();
      final decryptedContent = await compute(
        _decryptAndOTPBackup,
        _DecryptParams(fileBytes: fileBytes, password: password!),
      );
      entries = jsonDecode(decryptedContent) as List<dynamic>;
    } catch (e, s) {
      _logger.warning("Exception while decrypting andOTP backup", e, s);
      await dialog.hide();
      if (password != null) {
        if (!context.mounted) return null;
        await showErrorDialog(
          context,
          context.l10n.failedToDecryptAndOTPBackup,
          context.l10n.pleaseCheckPasswordAndTryAgain,
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

    // Skip unsupported types (e.g., MOTP)
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

      String otpUrl;
      if (type == 'TOTP' || type == 'STEAM') {
        final String otpType = type.toLowerCase();
        otpUrl =
            'otpauth://$otpType/$encodedIssuer:$encodedLabel?secret=$secret&issuer=$encodedIssuer&algorithm=$algorithm&digits=$digits&period=$period';
      } else {
        // HOTP
        otpUrl =
            'otpauth://hotp/$encodedIssuer:$encodedLabel?secret=$secret&issuer=$encodedIssuer&algorithm=$algorithm&digits=$digits&counter=$counter';
      }

      Code code = Code.fromOTPAuthUrl(otpUrl);
      if (tags.isNotEmpty) {
        code = code.copyWith(display: CodeDisplay(tags: tags));
      }
      parsedCodes.add(code);
    } catch (e, s) {
      _logger.warning('Failed to parse andOTP entry: $displayName', e, s);
    }
  }

  for (final code in parsedCodes) {
    await CodeStore.instance.addCode(code, shouldSync: false);
  }
  unawaited(AuthenticatorService.instance.onlineSync());

  return parsedCodes.length;
}

/// Top-level function for decrypting andOTP backup in a separate isolate.
/// Must be top-level (not a method or closure) to work with compute().
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

  // Extract iterations (4 bytes, big-endian)
  final ByteData byteData = ByteData.sublistView(fileBytes, 0, intLength);
  final int iterations = byteData.getInt32(0, Endian.big);

  // Extract salt (12 bytes)
  final Uint8List salt = Uint8List.sublistView(
    fileBytes,
    intLength,
    intLength + saltLength,
  );

  // Extract encrypted payload (IV + ciphertext + auth tag)
  final Uint8List encryptedPayload = Uint8List.sublistView(
    fileBytes,
    intLength + saltLength,
  );

  // Extract IV from encrypted payload (first 12 bytes)
  final Uint8List iv = Uint8List.sublistView(encryptedPayload, 0, ivLength);

  // Extract ciphertext + auth tag (remaining bytes)
  final Uint8List ciphertextWithTag = Uint8List.sublistView(
    encryptedPayload,
    ivLength,
  );

  // Derive key using PBKDF2 with HMAC-SHA1
  const int keyLength = 32; // 256 bits
  final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA1Digest(), 64));
  pbkdf2.init(Pbkdf2Parameters(salt, iterations, keyLength));

  final Uint8List derivedKey = Uint8List(keyLength);
  pbkdf2.deriveKey(Uint8List.fromList(utf8.encode(password)), 0, derivedKey, 0);

  // Decrypt using AES-GCM
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
