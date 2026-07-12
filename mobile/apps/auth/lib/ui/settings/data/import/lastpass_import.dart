import 'dart:async';
import 'dart:convert';

import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
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

Future<void> showLastpassImportInstruction(BuildContext context) async {
  final l10n = context.l10n;
  final result = await showDialogWidget(
    context: context,
    title: l10n.importFromApp("LastPass"),
    body: l10n.importLastpassGuide,
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
      await _pickLastpassJsonFile(context);
    }
  }
}

Future<void> _pickLastpassJsonFile(BuildContext context) async {
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
    int? count = await _processLastpassExportFile(context, path);
    await progressDialog.hide();
    if (count != null) {
      if (!context.mounted) return;
      await importSuccessDialog(context, count);
    }
  } catch (e, s) {
    Logger('LastPassImport').severe('exception while processing import', e, s);
    await progressDialog.hide();
    if (!context.mounted) return;
    await showErrorDialog(
      context,
      context.l10n.sorry,
      "${context.l10n.importFailureDesc}\n Error: ${e.toString()}",
    );
  }
}

Future<int?> _processLastpassExportFile(
  BuildContext context,
  String path,
) async {
  final jsonString = await readPickedImportFileAsString(path);
  Map<String, dynamic> jsonData = json.decode(jsonString);
  List<dynamic> accounts = jsonData["accounts"];
  final parsedCodes = [];
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

  for (final code in parsedCodes) {
    await CodeStore.instance.addCode(code, shouldSync: false);
  }
  unawaited(AuthenticatorService.instance.onlineSync());
  int count = parsedCodes.length;
  return count;
}
