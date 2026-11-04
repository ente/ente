import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/src/rust/api/import_api.dart' as rust;
import 'package:ente_auth/ui/settings/data/import/import_file_cleanup.dart';
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:ente_auth/ui/settings/data/import/proton_import_parser.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/progress_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

Future<void> showProtonImportInstruction(BuildContext context) async {
  final l10n = context.strings;
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
    dialogTitle: context.strings.importSelectJsonFile,
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

  late List<Code> parsedCodes;
  try {
    parsedCodes = await importProtonExport(jsonString);
  } on rust.ImportError_PasswordRequired {
    if (!context.mounted) return null;
    while (true) {
      if (!context.mounted) return null;
      final password = await promptForImportPassword(
        context,
        title: context.strings.passwordForDecryptingExport,
      );
      if (password == null) return null;
      await dialog.show();
      try {
        parsedCodes = await importProtonExport(jsonString, password: password);
        break;
      } on rust.ImportError_IncorrectPassword {
        await dialog.hide();
        if (!context.mounted) return null;
        await showErrorDialog(
          context,
          context.strings.incorrectPasswordTitle,
          context.strings.pleaseCheckPasswordAndTryAgain,
        );
      }
    }
  } on FormatException {
    if (!context.mounted) return null;
    await dialog.hide();
    if (!context.mounted) return null;
    await showErrorDialog(
      context,
      context.strings.invalidProtonExportTitle,
      context.strings.invalidProtonExportMessage,
    );
    return null;
  }
  return saveImportedCodes(parsedCodes);
}
