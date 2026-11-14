import 'package:ente_auth/src/rust/api/import_api.dart' as rust;
import 'package:ente_auth/ui/settings/data/import/import_file_cleanup.dart';
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:ente_auth/ui/settings/data/import/rust_import.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

Future<void> showLastpassImportInstruction(BuildContext context) async {
  final l10n = context.strings;
  await showFileImportInstruction(
    context: context,
    title: "LastPass Authenticator",
    body: l10n.importLastpassGuide,
    actionLabel: l10n.importSelectJsonFile,
    semanticsIdentifier: 'auth_import_instruction_lastpass',
    onImport: () => _pickLastpassJsonFile(context),
  );
}

Future<void> _pickLastpassJsonFile(BuildContext context) async {
  await pickAndProcessImportFile(
    context: context,
    logger: Logger('LastPassImport'),
    logMessage: 'Exception while processing LastPass import',
    process: (path, _) => _processLastpassExportFile(context, path),
  );
}

Future<int?> _processLastpassExportFile(
  BuildContext context,
  String path,
) async {
  final jsonString = await readPickedImportFileAsString(path);
  final codes = runRustImport(
    () => importCodes(rust.parseLastpass(export_: jsonString)),
  );
  return saveImportedCodes(codes);
}
