import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/ui/settings/data/import/import_file_cleanup.dart';
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:ente_auth/ui/settings/data/import/openauthenticator_import_parser.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/progress_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

Future<void> showOpenAuthenticatorImportInstruction(
  BuildContext context,
) async {
  final l10n = context.strings;
  await showFileImportInstruction(
    context: context,
    title: 'Open Authenticator',
    body: l10n.importOpenAuthenticatorGuide,
    actionLabel: l10n.selectFile,
    semanticsIdentifier: 'auth_import_instruction_open_authenticator',
    onImport: () => _pickBackupFile(context),
  );
}

Future<void> _pickBackupFile(BuildContext context) async {
  await pickAndProcessImportFile(
    context: context,
    dialogTitle: context.strings.selectFile,
    showProgressBeforeProcessing: false,
    logger: Logger('OpenAuthenticatorImport'),
    logMessage: 'Exception while processing Open Authenticator import',
    process: (path, progressDialog) =>
        _processBackup(context, path, progressDialog),
  );
}

Future<int?> _processBackup(
  BuildContext context,
  String path,
  ProgressDialog dialog,
) async {
  final backup = decodeOpenAuthenticatorBackup(
    await readPickedImportFileAsString(path),
  );
  while (true) {
    if (!context.mounted) return null;
    final password = await promptForImportPassword(
      context,
      title: context.strings.passwordForDecryptingExport,
    );
    if (password == null) return null;

    await dialog.show();
    try {
      final codes = await compute(_decryptBackup, (backup, password));
      return await saveImportedCodes(codes);
    } on IncorrectOpenAuthenticatorPasswordException {
      await dialog.hide();
      if (!context.mounted) return null;
      await showErrorDialog(
        context,
        context.strings.incorrectPasswordTitle,
        context.strings.pleaseCheckPasswordAndTryAgain,
      );
    }
  }
}

List<Code> _decryptBackup((Map<String, dynamic>, String) params) =>
    decryptOpenAuthenticatorBackup(params.$1, password: params.$2);
