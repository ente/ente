import 'dart:convert';

import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/models/export/ente.dart';
import 'package:ente_auth/ui/settings/data/import/import_file_cleanup.dart';
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:ente_auth/ui/settings/data/import/import_success.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_auth/utils/toast_util.dart';
import 'package:ente_crypto_api/ente_crypto_api.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

Future<void> showEncryptedImportInstruction(BuildContext context) async {
  final l10n = context.l10n;
  await showFileImportInstruction(
    context: context,
    title: "Ente Auth",
    body: l10n.importEnteEncGuide,
    actionLabel: l10n.importSelectJsonFile,
    semanticsIdentifier: 'auth_import_instruction_encrypted',
    onImport: () => _pickEnteJsonFile(context),
  );
}

Future<void> _decryptExportData(
  BuildContext context,
  EnteAuthExport enteAuthExport,
) async {
  final l10n = context.l10n;
  bool shouldRetry = false;
  int? importedCodeCount;
  await showTextInputDialog(
    context,
    title: l10n.passwordForDecryptingExport,
    submitButtonLabel: l10n.importLabel,
    hintText: l10n.enterYourPasswordHint,
    isPasswordInput: true,
    alwaysShowSuccessState: false,
    showOnlyLoadingState: true,
    onSubmit: (String password) async {
      if (password.isEmpty) {
        showToast(context, l10n.passwordEmptyError);
        shouldRetry = true;
        return;
      }
      final progressDialog = createProgressDialog(context, l10n.pleaseWait);
      try {
        if (!context.mounted) return;
        await progressDialog.show();
        final derivedKey = await CryptoUtil.deriveKey(
          utf8.encode(password),
          CryptoUtil.base642bin(enteAuthExport.kdfParams.salt),
          enteAuthExport.kdfParams.memLimit,
          enteAuthExport.kdfParams.opsLimit,
        );
        late final Uint8List decryptedContent;
        try {
          decryptedContent = await CryptoUtil.decryptData(
            CryptoUtil.base642bin(enteAuthExport.encryptedData),
            derivedKey,
            CryptoUtil.base642bin(enteAuthExport.encryptionNonce),
          );
        } catch (e, s) {
          Logger("encryptedImport").warning('failed to decrypt', e, s);
          if (!context.mounted) return;
          showToast(context, l10n.incorrectPasswordTitle);
          shouldRetry = true;
          await progressDialog.hide();
          return;
        }
        String content = utf8.decode(decryptedContent);
        List<String> splitCodes = content.split("\n");
        final parsedCodes = <Code>[];
        for (final code in splitCodes) {
          try {
            parsedCodes.add(Code.fromOTPAuthUrl(code));
          } catch (e) {
            Logger('EncryptedText').severe("Could not parse code", e);
          }
        }
        importedCodeCount = await saveImportedCodes(parsedCodes);
        await progressDialog.hide();
      } catch (e, s) {
        await progressDialog.hide();
        if (!context.mounted) return;
        Logger("ExportWidget").severe(e, s);
        if (!context.mounted) return;
        showToast(context, "Error while exporting codes.");
      }
    },
  );
  if (shouldRetry) {
    if (!context.mounted) return;
    await _decryptExportData(context, enteAuthExport);
    return;
  }
  if (importedCodeCount != null) {
    if (!context.mounted) return;
    await importSuccessDialog(context, importedCodeCount!);
  }
}

Future<void> _pickEnteJsonFile(BuildContext context) async {
  FilePickerResult? result = await FilePicker.platform.pickFiles();
  if (result == null) {
    return;
  }

  try {
    if (!context.mounted) return;
    final jsonString = await readPickedImportFileAsString(
      result.files.single.path!,
    );
    EnteAuthExport exportedData = EnteAuthExport.fromJson(
      jsonDecode(jsonString),
    );
    if (!context.mounted) return;
    await _decryptExportData(context, exportedData);
  } catch (e) {
    if (!context.mounted) return;
    await showErrorDialog(
      context,
      context.l10n.sorry,
      context.l10n.importFailureDesc,
    );
  }
}
