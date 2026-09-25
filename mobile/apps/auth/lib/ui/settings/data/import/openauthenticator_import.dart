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
    title: l10n.importTypeOpenAuthenticator,
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
  final jsonString = await readPickedImportFileAsString(path);

  // Validate the shape before asking for a password, so an unrelated file
  // fails fast instead of looking like a wrong password.
  try {
    decodeOpenAuthenticatorBackup(jsonString);
  } on InvalidOpenAuthenticatorBackupException {
    if (!context.mounted) return null;
    await dialog.hide();
    if (!context.mounted) return null;
    await showErrorDialog(
      context,
      context.strings.sorry,
      context.strings.importFailureDesc,
    );
    return null;
  }

  while (true) {
    if (!context.mounted) return null;
    final password = await promptForImportPassword(
      context,
      title: context.strings.passwordForDecryptingExport,
    );
    if (password == null) return null;

    await dialog.show();
    final result = await compute(_decryptBackupInBackground, {
      'jsonString': jsonString,
      'password': password,
    });

    switch (result['status']) {
      case 'incorrect_password':
        await dialog.hide();
        if (!context.mounted) return null;
        await showErrorDialog(
          context,
          context.strings.incorrectPasswordTitle,
          context.strings.pleaseCheckPasswordAndTryAgain,
        );
        continue;
      case 'entry_error':
        throwImportEntryParseError(
          result['entry'],
          result['error'] ?? 'Could not decrypt entry',
        );
      case 'ok':
        final entries = (result['entries'] as List)
            .cast<Map<String, Object?>>();
        return saveImportedCodes(parseOpenAuthenticatorEntries(entries));
      default:
        throw StateError('Unexpected Open Authenticator decrypt status');
    }
  }
}

/// Runs on a background isolate; the parser and its exceptions never leave it.
Map<String, Object?> _decryptBackupInBackground(Map<String, String> params) {
  final jsonString = params['jsonString'];
  final password = params['password'];
  if (jsonString == null || password == null) {
    throw ArgumentError('Missing Open Authenticator decryption params');
  }

  final backup = decodeOpenAuthenticatorBackup(jsonString);
  try {
    return {
      'status': 'ok',
      'entries': decryptOpenAuthenticatorBackup(backup, password: password),
    };
  } on IncorrectOpenAuthenticatorPasswordException {
    return {'status': 'incorrect_password'};
  } on OpenAuthenticatorEntryParseException catch (error) {
    return {
      'status': 'entry_error',
      'entry': error.entry,
      'error': error.error.toString(),
    };
  }
}
