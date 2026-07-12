import 'dart:async';
import 'dart:convert';

import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/models/code_display.dart';
import 'package:ente_auth/services/authenticator_service.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/ui/components/buttons/button_widget.dart';
import 'package:ente_auth/ui/components/dialog_widget.dart';
import 'package:ente_auth/ui/components/models/button_type.dart';
import 'package:ente_auth/ui/settings/data/import/import_file_cleanup.dart';
import 'package:ente_auth/ui/settings/data/import/import_success.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

Future<void> showBitwardenImportInstruction(BuildContext context) async {
  final l10n = context.l10n;
  final result = await showDialogWidget(
    context: context,
    title: l10n.importFromApp("Bitwarden"),
    body: l10n.importBitwardenGuide,
    buttons: [
      ButtonWidget(
        buttonType: ButtonType.primary,
        labelText: l10n.importSelectJsonFile,
        isInAlert: true,
        buttonSize: ButtonSize.large,
        buttonAction: ButtonAction.first,
      ),
      ButtonWidget(
        buttonType: ButtonType.secondary,
        labelText: context.l10n.cancel,
        buttonSize: ButtonSize.large,
        isInAlert: true,
        buttonAction: ButtonAction.second,
      ),
    ],
  );
  if (result?.action != null && result!.action != ButtonAction.cancel) {
    if (!context.mounted) return;
    if (result.action == ButtonAction.first) {
      await _pickBitwardenJsonFile(context);
    }
  }
}

Future<void> _pickBitwardenJsonFile(BuildContext context) async {
  final l10n = context.l10n;
  FilePickerResult? result = await FilePicker.platform.pickFiles();
  if (result == null) {
    return;
  }
  if (!context.mounted) return;
  final progressDialog = createProgressDialog(context, l10n.pleaseWait);
  await progressDialog.show();
  try {
    if (!context.mounted) return;
    String path = result.files.single.path!;
    int? count = await _processBitwardenExportFile(context, path);
    await progressDialog.hide();
    if (count != null) {
      if (!context.mounted) return;
      await importSuccessDialog(context, count);
    }
  } catch (e, s) {
    Logger("BitwardenImport").severe('Failed to import', e, s);
    await progressDialog.hide();
    if (!context.mounted) return;
    await showErrorDialog(
      context,
      context.l10n.sorry,
      "${context.l10n.importFailureDesc}\n Error: ${e.toString()}",
    );
  }
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
  final parsedCodes = [];
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

  for (final code in parsedCodes) {
    await CodeStore.instance.addCode(code, shouldSync: false);
  }
  unawaited(AuthenticatorService.instance.onlineSync());
  return parsedCodes.length;
}
