import 'dart:convert';

import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/models/code_display.dart';
import 'package:ente_auth/ui/settings/data/import/import_file_cleanup.dart';
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

Future<void> showBitwardenImportInstruction(BuildContext context) async {
  final l10n = context.l10n;
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
  final data = jsonDecode(jsonString);
  List<dynamic> jsonArray = data['items'];
  final Map<String, String> folderIdToName = {};
  try {
    for (var item in data['folders']) {
      folderIdToName[item['id']] = item['name'];
    }
  } catch (e) {
    debugPrint("Failed to get folder details $e");
  }
  final parsedCodes = <Code>[];
  for (var item in jsonArray) {
    if (item['login'] != null && item['login']['totp'] != null) {
      var totp = item['login']['totp'];
      String? folderID = item['folderId'];

      Code code;
      if (totp.contains("otpauth://")) {
        code = Code.fromOTPAuthUrl(totp);
      } else if (totp.contains("steam://")) {
        var secret = totp.split("steam://")[1];
        code = Code.fromAccountAndSecret(
          Type.steam,
          item['login']['username'],
          item['name'],
          secret,
          null,
          Code.steamDigits,
        );
      } else {
        var issuer = item['name'] ?? '';
        var account = item['login']['username'] ?? '';
        code = Code.fromAccountAndSecret(
          Type.totp,
          account,
          issuer,
          totp,
          null,
          Code.defaultDigits,
        );
      }
      if (folderID != null && folderIdToName.containsKey(folderID)) {
        code = code.copyWith(
          display: CodeDisplay(tags: [folderIdToName[folderID]!]),
        );
      }

      parsedCodes.add(code);
    }
  }

  return saveImportedCodes(parsedCodes);
}
