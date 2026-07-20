import 'dart:convert';

import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/ui/settings/data/import/import_file_cleanup.dart';
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

Future<void> showLastpassImportInstruction(BuildContext context) async {
  final l10n = context.l10n;
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
  Map<String, dynamic> jsonData = json.decode(jsonString);
  List<dynamic> accounts = jsonData["accounts"];
  final parsedCodes = <Code>[];
  for (var item in accounts) {
    var algorithm = item['algorithm'];
    var timer = item['timeStep'];
    var digits = item['digits'];
    var issuer = item['issuerName'];
    var secret = item['secret'];
    var account = item['userName'];

    // Build the OTP URL
    String otpUrl =
        'otpauth://totp/$issuer:$account?secret=$secret&issuer=$issuer&algorithm=$algorithm&digits=$digits&period=$timer';
    parsedCodes.add(Code.fromOTPAuthUrl(otpUrl));
  }

  return saveImportedCodes(parsedCodes);
}
