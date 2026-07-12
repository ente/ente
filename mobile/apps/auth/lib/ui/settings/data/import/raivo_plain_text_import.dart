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

Future<void> showRaivoImportInstruction(BuildContext context) async {
  final l10n = context.l10n;
  final result = await showDialogWidget(
    context: context,
    title: l10n.importFromApp("Raivo OTP"),
    body: l10n.importRaivoGuide,
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
      await _pickRaivoJsonFile(context);
    } else {}
  }
}

Future<void> _pickRaivoJsonFile(BuildContext context) async {
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
    int? count = await _processRaivoExportFile(context, path);
    await progressDialog.hide();
    if (count != null) {
      if (!context.mounted) return;
      await importSuccessDialog(context, count);
    }
  } catch (e, s) {
    Logger("RaivoImport").severe('Failed to import', e, s);
    await progressDialog.hide();
    if (!context.mounted) return;
    await showErrorDialog(
      context,
      context.l10n.sorry,
      "${context.l10n.importFailureDesc}\n Error: ${e.toString()}",
    );
  }
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
  final parsedCodes = [];
  for (var item in jsonArray) {
    var kind = item['kind'];
    var algorithm = item['algorithm'];
    var timer = item['timer'];
    var digits = item['digits'];
    var issuer = item['issuer'];
    var secret = item['secret'];
    var account = item['account'];
    var counter = item['counter'];

    // Build the OTP URL
    String otpUrl;

    if (kind.toLowerCase() == 'totp') {
      otpUrl =
          'otpauth://$kind/$issuer:$account?secret=$secret&issuer=$issuer&algorithm=$algorithm&digits=$digits&period=$timer';
    } else if (kind.toLowerCase() == 'hotp') {
      otpUrl =
          'otpauth://$kind/$issuer:$account?secret=$secret&issuer=$issuer&algorithm=$algorithm&digits=$digits&counter=$counter';
    } else {
      throw Exception('Invalid OTP type $kind');
    }
    parsedCodes.add(Code.fromOTPAuthUrl(otpUrl));
  }

  for (final code in parsedCodes) {
    await CodeStore.instance.addCode(code, shouldSync: false);
  }
  unawaited(AuthenticatorService.instance.onlineSync());
  int count = parsedCodes.length;
  return count;
}
