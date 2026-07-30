import 'dart:async';
import 'dart:convert';

import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/services/authenticator_service.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/ui/components/buttons/button_widget.dart';
import 'package:ente_auth/ui/settings/data/import/import_instruction_sheet.dart';
import 'package:ente_auth/ui/settings/data/import/import_success.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_ui/components/progress_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

typedef ImportFileProcessor =
    Future<int?> Function(String path, ProgressDialog progressDialog);

const _maxImportedOtpDigits = 10;

class ImportEntryParseException implements Exception {
  final Object? entry;
  final Object error;

  const ImportEntryParseException({required this.entry, required this.error});

  String get errorText => error.toString();

  String get entryText {
    final failedEntry = entry;
    if (failedEntry is String) return failedEntry;
    try {
      return const JsonEncoder.withIndent('  ').convert(failedEntry);
    } catch (_) {
      return failedEntry.toString();
    }
  }

  String get details => 'Error: $errorText\n\nEntry:\n$entryText';

  @override
  String toString() => 'Could not parse import entry: $errorText';
}

Never throwImportEntryParseError(Object? entry, Object error) {
  if (error is ImportEntryParseException) throw error;
  throw ImportEntryParseException(entry: entry, error: error);
}

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
    final message =
        errorMessage?.call(context, error) ??
        '${context.l10n.importFailureDesc}\n Error: $error';
    if (error is ImportEntryParseException) {
      await _showImportEntryParseError(context, error, message);
    } else {
      await showErrorDialog(context, context.l10n.sorry, message);
    }
  }
}

Future<void> _showImportEntryParseError(
  BuildContext context,
  ImportEntryParseException error,
  String message,
) async {
  final result = await showChoiceDialog(
    context,
    title: context.l10n.sorry,
    body: message,
    firstButtonLabel: 'View entry',
    secondButtonLabel: context.l10n.ok,
  );
  if (result?.action != ButtonAction.first || !context.mounted) return;

  await showErrorDialog(
    context,
    'Failed import entry',
    error.details,
    showContactSupport: false,
  );
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

Code parseImportOtpCode(Object? entry, String Function() buildUri) {
  try {
    return Code.fromOTPAuthUrl(buildUri());
  } catch (error) {
    throwImportEntryParseError(entry, error);
  }
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
  final normalizedDigits = _normalizeImportedOtpDigits(digits);
  if (normalizedKind == 'totp' || (allowSteam && normalizedKind == 'steam')) {
    final normalizedPeriod = _normalizeImportedOtpPeriod(period);
    return 'otpauth://$normalizedKind/$issuer:$account?secret=$secret&issuer=$issuer&algorithm=$algorithm&digits=$normalizedDigits&period=$normalizedPeriod';
  }
  if (normalizedKind == 'hotp') {
    final normalizedCounter = _normalizeImportedOtpCounter(counter);
    return 'otpauth://hotp/$issuer:$account?secret=$secret&issuer=$issuer&algorithm=$algorithm&digits=$normalizedDigits&counter=$normalizedCounter';
  }
  throw FormatException('Invalid OTP type: $kind');
}

int _normalizeImportedOtpDigits(Object? digits) {
  final parsedDigits = _parseImportedOtpInt(digits);
  if (parsedDigits == null || parsedDigits == 0) return Code.defaultDigits;
  if (parsedDigits < 0 || parsedDigits > _maxImportedOtpDigits) {
    throw FormatException('Invalid OTP digits: $parsedDigits');
  }
  return parsedDigits;
}

int _normalizeImportedOtpPeriod(Object? period) {
  final parsedPeriod = _parseImportedOtpInt(period);
  if (parsedPeriod == null || parsedPeriod <= 0) return Code.defaultPeriod;
  return parsedPeriod;
}

int _normalizeImportedOtpCounter(Object? counter) {
  final parsedCounter = _parseImportedOtpInt(counter);
  if (parsedCounter == null) return 0;
  if (parsedCounter < 0) {
    throw FormatException('Invalid HOTP counter: $parsedCounter');
  }
  return parsedCounter;
}

int? _parseImportedOtpInt(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

Future<int> saveImportedCodes(Iterable<Code> codes) async {
  final importedCodes = codes.toList(growable: false);
  for (final code in importedCodes) {
    await CodeStore.instance.addCode(code, shouldSync: false);
  }
  unawaited(AuthenticatorService.instance.onlineSync());
  return importedCodes.length;
}
