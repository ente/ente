import 'dart:async';

import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/services/authenticator_service.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/ui/settings/data/import/import_instruction_sheet.dart';
import 'package:ente_auth/ui/settings/data/import/import_success.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_ui/components/progress_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

typedef ImportFileProcessor =
    Future<int?> Function(String path, ProgressDialog progressDialog);

Future<void> showFileImportInstruction({
  required BuildContext context,
  required String title,
  required String actionLabel,
  required String semanticsIdentifier,
  required Future<void> Function() onImport,
  String? body,
  Widget? content,
}) async {
  final result = await showImportInstructionSheet(
    context: context,
    title: title,
    body: body,
    content: content,
    cancelLabel: context.l10n.cancel,
    semanticsIdentifier: semanticsIdentifier,
    actions: [
      ImportInstructionAction(
        label: actionLabel,
        result: ImportInstructionResult.primary,
      ),
    ],
  );
  if (result != ImportInstructionResult.primary || !context.mounted) return;
  await onImport();
}

Future<void> pickAndProcessImportFile({
  required BuildContext context,
  required Logger logger,
  required String logMessage,
  required ImportFileProcessor process,
  String? dialogTitle,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  bool showProgressBeforeProcessing = true,
  String Function(BuildContext context, Object error)? errorMessage,
}) async {
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: dialogTitle,
    allowMultiple: false,
    type: type,
    allowedExtensions: allowedExtensions,
  );
  if (result == null || !context.mounted) return;

  final progressDialog = createProgressDialog(context, context.l10n.pleaseWait);
  try {
    if (showProgressBeforeProcessing) {
      await progressDialog.show();
    }
    if (!context.mounted) return;
    final count = await process(result.files.single.path!, progressDialog);
    await progressDialog.hide();
    if (count != null && context.mounted) {
      await importSuccessDialog(context, count);
    }
  } catch (error, stackTrace) {
    logger.severe(logMessage, error, stackTrace);
    await progressDialog.hide();
    if (!context.mounted) return;
    await showErrorDialog(
      context,
      context.l10n.sorry,
      errorMessage?.call(context, error) ??
          '${context.l10n.importFailureDesc}\n Error: $error',
    );
  }
}

Future<String?> promptForImportPassword(
  BuildContext context, {
  required String title,
}) async {
  String? password;
  await showTextInputDialog(
    context,
    title: title,
    submitButtonLabel: context.l10n.submit,
    isPasswordInput: true,
    onSubmit: (value) async {
      password = value;
    },
  );
  return password;
}

String buildImportOtpUri({
  required String kind,
  required Object issuer,
  required Object account,
  required Object secret,
  required Object algorithm,
  required Object digits,
  Object? period,
  Object? counter,
  bool allowSteam = true,
}) {
  final normalizedKind = kind.toLowerCase();
  if (normalizedKind == 'totp' || (allowSteam && normalizedKind == 'steam')) {
    return 'otpauth://$normalizedKind/$issuer:$account?secret=$secret&issuer=$issuer&algorithm=$algorithm&digits=$digits&period=$period';
  }
  if (normalizedKind == 'hotp') {
    return 'otpauth://hotp/$issuer:$account?secret=$secret&issuer=$issuer&algorithm=$algorithm&digits=$digits&counter=$counter';
  }
  throw FormatException('Invalid OTP type: $kind');
}

Future<int> saveImportedCodes(Iterable<Code> codes) async {
  final importedCodes = codes.toList(growable: false);
  for (final code in importedCodes) {
    await CodeStore.instance.addCode(code, shouldSync: false);
  }
  unawaited(AuthenticatorService.instance.onlineSync());
  return importedCodes.length;
}
