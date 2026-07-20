import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/ui/settings/data/import/import_file_cleanup.dart';
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:ente_auth/ui/settings/data/import/proton_import_parser.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_ui/components/progress_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

Future<void> showProtonImportInstruction(BuildContext context) async {
  final l10n = context.l10n;
  await showFileImportInstruction(
    context: context,
    title: "Proton Authenticator",
    body: l10n.importProtonAuthGuide,
    actionLabel: l10n.importSelectJsonFile,
    semanticsIdentifier: 'auth_import_instruction_proton',
    onImport: () => _pickProtonJsonFile(context),
  );
}

Future<void> _pickProtonJsonFile(BuildContext context) async {
  await pickAndProcessImportFile(
    context: context,
    dialogTitle: context.l10n.importSelectJsonFile,
    showProgressBeforeProcessing: false,
    logger: Logger('ProtonImport'),
    logMessage: 'Exception while processing Proton import',
    process: (path, progressDialog) =>
        _processProtonExportFile(context, path, progressDialog),
  );
}

Future<int?> _processProtonExportFile(
  BuildContext context,
  String path,
  ProgressDialog dialog,
) async {
  final jsonString = await readPickedImportFileAsString(path);

  Map<String, dynamic> decodedJson;
  try {
    decodedJson = decodeProtonExportJson(jsonString);
  } on FormatException {
    if (!context.mounted) return null;
    await dialog.hide();
    if (!context.mounted) return null;
    await showErrorDialog(
      context,
      context.l10n.invalidProtonExportTitle,
      context.l10n.invalidProtonExportMessage,
    );
    return null;
  }

  if (isEncryptedProtonExport(decodedJson)) {
    if (!context.mounted) return null;
    while (true) {
      if (!context.mounted) return null;
      final password = await promptForImportPassword(
        context,
        title: context.l10n.passwordForDecryptingExport,
      );
      if (password == null) {
        return null;
      }

      await dialog.show();
      try {
        final decryptedJsonResult = await compute(
          _decryptProtonExportInBackground,
          {'jsonString': jsonString, 'password': password},
        );
        switch (decryptedJsonResult['status']) {
          case 'incorrect_password':
            await dialog.hide();
            if (!context.mounted) return null;
            await showErrorDialog(
              context,
              context.l10n.incorrectPasswordTitle,
              context.l10n.pleaseCheckPasswordAndTryAgain,
            );
            continue;
          case 'ok':
            decodedJson = decodeProtonExportJson(
              decryptedJsonResult['jsonString']!,
            );
            break;
          default:
            throw StateError('Unexpected Proton decrypt result status');
        }
        break;
      } catch (e, s) {
        Logger('ProtonImport').warning('Failed to decrypt Proton export', e, s);
        rethrow;
      }
    }
  } else {
    await dialog.show();
  }

  final parsedCodes = parseProtonExport(decodedJson);
  return saveImportedCodes(parsedCodes);
}

Map<String, String> _decryptProtonExportInBackground(
  Map<String, String> params,
) {
  final jsonString = params['jsonString'];
  final password = params['password'];
  if (jsonString == null || password == null) {
    throw ArgumentError('Missing Proton export decryption params');
  }

  final decodedJson = decodeProtonExportJson(jsonString);
  try {
    return {
      'status': 'ok',
      'jsonString': decryptProtonExport(decodedJson, password: password),
    };
  } on IncorrectProtonExportPasswordException {
    return {'status': 'incorrect_password'};
  }
}
