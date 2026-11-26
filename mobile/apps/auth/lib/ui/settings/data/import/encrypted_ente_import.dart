import 'dart:typed_data';

import 'package:ente_auth/src/rust/api/import_api.dart' as rust;
import 'package:ente_auth/ui/settings/data/import/import_file_cleanup.dart';
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:ente_auth/ui/settings/data/import/import_success.dart';
import 'package:ente_auth/ui/settings/data/import/rust_import.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_auth/utils/toast_util.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

Future<void> showEncryptedImportInstruction(BuildContext context) async {
  final l10n = context.strings;
  await showFileImportInstruction(
    context: context,
    title: "Ente Auth",
    body: l10n.importEnteEncGuide,
    actionLabel: l10n.importSelectJsonFile,
    semanticsIdentifier: 'auth_import_instruction_encrypted',
    onImport: () => _pickEnteJsonFile(context),
  );
}

Future<void> _decryptExportData(BuildContext context, Uint8List export) async {
  final l10n = context.strings;
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
        final parsedCodes = await runRustImportAsync(
          () async => importCodes(
            await rust.decryptEnteBackup(input: export, password: password),
            logger: Logger('EncryptedText'),
            source: 'Ente Auth backup',
          ),
        );
        importedCodeCount = await saveImportedCodes(parsedCodes);
        await progressDialog.hide();
      } on rust.ImportError_IncorrectPassword catch (e, s) {
        Logger("encryptedImport").warning('failed to decrypt', e, s);
        await progressDialog.hide();
        if (!context.mounted) return;
        showToast(context, l10n.incorrectPasswordTitle);
        shouldRetry = true;
      } catch (e, s) {
        await progressDialog.hide();
        if (!context.mounted) return;
        Logger("ExportWidget").severe(e, s);
        await showErrorDialog(
          context,
          context.strings.sorry,
          context.strings.importFailureDesc,
        );
      }
    },
  );
  if (shouldRetry) {
    if (!context.mounted) return;
    await _decryptExportData(context, export);
    return;
  }
  if (importedCodeCount != null) {
    if (!context.mounted) return;
    await importSuccessDialog(context, importedCodeCount!);
  }
}

Future<void> _pickEnteJsonFile(BuildContext context) async {
  FilePickerResult? result = await FilePicker.pickFiles();
  if (result == null) {
    return;
  }

  try {
    if (!context.mounted) return;
    final bytes = await readPickedImportFileAsBytes(result.files.single.path!);
    runRustImport(() => rust.validateEnteBackup(input: bytes));
    if (!context.mounted) return;
    await _decryptExportData(context, bytes);
  } catch (e) {
    if (!context.mounted) return;
    await showErrorDialog(
      context,
      context.strings.sorry,
      context.strings.importFailureDesc,
    );
  }
}
