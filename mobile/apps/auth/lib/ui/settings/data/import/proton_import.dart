import 'dart:async';

import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/services/authenticator_service.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/ui/components/buttons/button_widget.dart';
import 'package:ente_auth/ui/components/dialog_widget.dart';
import 'package:ente_auth/ui/components/models/button_type.dart';
import 'package:ente_auth/ui/settings/data/import/import_file_cleanup.dart';
import 'package:ente_auth/ui/settings/data/import/import_success.dart';
import 'package:ente_auth/ui/settings/data/import/proton_import_parser.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_ui/components/progress_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

Future<void> showProtonImportInstruction(BuildContext context) async {
  final l10n = context.l10n;
  final result = await showDialogWidget(
    context: context,
    title: l10n.importFromApp("Proton Authenticator"),
    body: l10n.importProtonAuthGuide,
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
      await _pickProtonJsonFile(context);
    }
  }
}

Future<void> _pickProtonJsonFile(BuildContext context) async {
  final l10n = context.l10n;
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: l10n.importSelectJsonFile,
  );
  if (result == null) {
    return;
  }

  if (!context.mounted) return;
  final progressDialog = createProgressDialog(context, l10n.pleaseWait);
  try {
    if (!context.mounted) return;
    final path = result.files.single.path!;
    final count = await _processProtonExportFile(context, path, progressDialog);
    await progressDialog.hide();
    if (count != null) {
      if (!context.mounted) return;
      await importSuccessDialog(context, count);
    }
  } catch (e, s) {
    Logger(
      'ProtonImport',
    ).severe('Exception while processing Proton import', e, s);
    await progressDialog.hide();
    if (!context.mounted) return;
    await showErrorDialog(
      context,
      context.l10n.sorry,
      "${context.l10n.importFailureDesc}\n Error: ${e.toString()}",
    );
  }
}

Future<int?> _processProtonExportFile(
  BuildContext context,
  String path,
  ProgressDialog dialog,
) async {
  final jsonString = await readPickedImportFileAsString(path);

  Map<String, dynamic> decodedJson;
  try {
    decodedJson = decodeProtonExportJson(jsonString);
  } on FormatException {
    if (!context.mounted) return null;
    await dialog.hide();
    if (!context.mounted) return null;
    await showErrorDialog(
      context,
      context.l10n.invalidProtonExportTitle,
      context.l10n.invalidProtonExportMessage,
    );
    return null;
  }

  if (isEncryptedProtonExport(decodedJson)) {
    if (!context.mounted) return null;
    while (true) {
      if (!context.mounted) return null;
      final password = await _promptForProtonExportPassword(context);
      if (password == null) {
        return null;
      }

      await dialog.show();
      try {
        final decryptedJsonResult = await compute(
          _decryptProtonExportInBackground,
          {'jsonString': jsonString, 'password': password},
        );
        switch (decryptedJsonResult['status']) {
          case 'incorrect_password':
            await dialog.hide();
            if (!context.mounted) return null;
            await showErrorDialog(
              context,
              context.l10n.incorrectPasswordTitle,
              context.l10n.pleaseCheckPasswordAndTryAgain,
            );
            continue;
          case 'ok':
            decodedJson = decodeProtonExportJson(
              decryptedJsonResult['jsonString']!,
            );
            break;
          default:
            throw StateError('Unexpected Proton decrypt result status');
        }
        break;
      } catch (e, s) {
        Logger('ProtonImport').warning('Failed to decrypt Proton export', e, s);
        rethrow;
      }
    }
  } else {
    await dialog.show();
  }

  final parsedCodes = parseProtonExport(decodedJson);
  for (final code in parsedCodes) {
    await CodeStore.instance.addCode(code, shouldSync: false);
  }

  unawaited(AuthenticatorService.instance.onlineSync());
  return parsedCodes.length;
}

Map<String, String> _decryptProtonExportInBackground(
  Map<String, String> params,
) {
  final jsonString = params['jsonString'];
  final password = params['password'];
  if (jsonString == null || password == null) {
    throw ArgumentError('Missing Proton export decryption params');
  }

  final decodedJson = decodeProtonExportJson(jsonString);
  try {
    return {
      'status': 'ok',
      'jsonString': decryptProtonExport(decodedJson, password: password),
    };
  } on IncorrectProtonExportPasswordException {
    return {'status': 'incorrect_password'};
  }
}

Future<String?> _promptForProtonExportPassword(BuildContext context) async {
  String? password;
  await showTextInputDialog(
    context,
    title: context.l10n.passwordForDecryptingExport,
    submitButtonLabel: context.l10n.submit,
    isPasswordInput: true,
    onSubmit: (value) async {
      password = value;
    },
  );
  return password;
}
