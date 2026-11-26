import 'package:ente_auth/src/rust/api/import_api.dart' as rust;
import 'package:ente_auth/ui/settings/data/import/import_file_cleanup.dart';
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:ente_auth/ui/settings/data/import/rust_import.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

Future<void> showBitwardenImportInstruction(BuildContext context) async {
  final l10n = context.strings;
  await showFileImportInstruction(
    context: context,
    title: "Bitwarden",
    body: l10n.importBitwardenGuide,
    actionLabel: l10n.importSelectJsonFile,
    semanticsIdentifier: 'auth_import_instruction_bitwarden',
    onImport: () => _pickBitwardenJsonFile(context),
  );
}

Future<void> _pickBitwardenJsonFile(BuildContext context) async {
  await pickAndProcessImportFile(
    context: context,
    logger: Logger('BitwardenImport'),
    logMessage: 'Failed to import Bitwarden export',
    process: (path, _) => _processBitwardenExportFile(context, path),
  );
}

Future<int?> _processBitwardenExportFile(
  BuildContext context,
  String path,
) async {
  final jsonString = await readPickedImportFileAsString(path);
  final codes = runRustImport(
    () => importCodes(rust.parseBitwarden(export_: jsonString)),
  );
  return saveImportedCodes(codes);
}
