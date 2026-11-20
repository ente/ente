import 'package:ente_auth/src/rust/api/import_api.dart' as rust;
import 'package:ente_auth/ui/settings/data/import/import_file_cleanup.dart';
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:ente_auth/ui/settings/data/import/rust_import.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

Future<void> showRaivoImportInstruction(BuildContext context) async {
  final l10n = context.strings;
  await showFileImportInstruction(
    context: context,
    title: "Raivo OTP",
    body: l10n.importRaivoGuide,
    actionLabel: l10n.importSelectJsonFile,
    semanticsIdentifier: 'auth_import_instruction_raivo',
    onImport: () => _pickRaivoJsonFile(context),
  );
}

Future<void> _pickRaivoJsonFile(BuildContext context) async {
  await pickAndProcessImportFile(
    context: context,
    logger: Logger('RaivoImport'),
    logMessage: 'Failed to import Raivo export',
    process: (path, _) => _processRaivoExportFile(context, path),
  );
}

Future<int?> _processRaivoExportFile(BuildContext context, String path) async {
  if (path.endsWith('.zip')) {
    if (!context.mounted) return null;
    await deletePickedImportFileIfAppOwned(path);
    if (!context.mounted) return null;
    await showErrorDialog(
      context,
      context.strings.sorry,
      "We don't support zip files yet. Please unzip the file and try again.",
    );
    return null;
  }
  final jsonString = await readPickedImportFileAsString(path);
  final codes = runRustImport(
    () => importCodes(rust.parseRaivo(export_: jsonString)),
  );
  return saveImportedCodes(codes);
}
