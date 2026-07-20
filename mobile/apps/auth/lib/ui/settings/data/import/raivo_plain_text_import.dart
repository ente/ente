import 'dart:convert';

import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/ui/settings/data/import/import_file_cleanup.dart';
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

Future<void> showRaivoImportInstruction(BuildContext context) async {
  final l10n = context.l10n;
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
      context.l10n.sorry,
      "We don't support zip files yet. Please unzip the file and try again.",
    );
    return null;
  }
  final jsonString = await readPickedImportFileAsString(path);
  List<dynamic> jsonArray = jsonDecode(jsonString);
  final parsedCodes = <Code>[];
  for (var item in jsonArray) {
    var kind = item['kind'];
    var algorithm = item['algorithm'];
    var timer = item['timer'];
    var digits = item['digits'];
    var issuer = item['issuer'];
    var secret = item['secret'];
    var account = item['account'];
    var counter = item['counter'];

    parsedCodes.add(
      Code.fromOTPAuthUrl(
        buildImportOtpUri(
          kind: kind,
          issuer: issuer,
          account: account,
          secret: secret,
          algorithm: algorithm,
          digits: digits,
          period: timer,
          counter: counter,
          allowSteam: false,
        ),
      ),
    );
  }

  return saveImportedCodes(parsedCodes);
}
