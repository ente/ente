import 'package:ente_auth/src/rust/api/import_api.dart' as rust;
import 'package:ente_auth/ui/settings/data/import/import_file_cleanup.dart';
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:ente_auth/ui/settings/data/import/rust_import.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/progress_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

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

Future<int?> _processAndOTPFile(
  BuildContext context,
  String path,
  ProgressDialog dialog,
) async {
  final fileBytes = await readPickedImportFileAsBytes(path);
  late rust.ImportBatch batch;
  try {
    batch = await runRustImportAsync(() => rust.importAndotp(input: fileBytes));
    await dialog.show();
  } on rust.ImportError_PasswordRequired {
    if (!context.mounted) return null;
    final password = await promptForImportPassword(
      context,
      title: context.strings.enterPasswordToDecryptAndOTP,
    );
    if (password == null) {
      return null;
    }
    await dialog.show();
    try {
      batch = await runRustImportAsync(
        () => rust.importAndotp(input: fileBytes, password: password),
      );
    } on rust.ImportError_IncorrectPassword catch (e, s) {
      _logger.warning("Exception while decrypting andOTP backup", e, s);
      await dialog.hide();
      if (!context.mounted) return null;
      await showErrorDialog(
        context,
        context.strings.failedToDecryptAndOTPBackup,
        context.strings.pleaseCheckPasswordAndTryAgain,
      );
      return null;
    }
  }
  return saveImportedCodes(
    importCodes(batch, logger: _logger, source: 'andOTP'),
  );
}
