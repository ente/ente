import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/ui/settings/data/import/import_file_cleanup.dart';
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:ente_auth/ui/settings/data/import/otp_auth_import_parser.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_ui/components/progress_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

final _logger = Logger('OtpAuthImport');

Future<void> showOtpAuthImportInstruction(BuildContext context) async {
  final l10n = context.l10n;
  await showFileImportInstruction(
    context: context,
    title: 'OTP Auth',
    body: l10n.importOtpAuthGuide,
    actionLabel: l10n.importSelectAppExport('OTP Auth'),
    semanticsIdentifier: 'auth_import_instruction_otp_auth',
    onImport: () => _pickOtpAuthFile(context),
  );
}

Future<void> _pickOtpAuthFile(BuildContext context) async {
  await pickAndProcessImportFile(
    context: context,
    dialogTitle: context.l10n.importSelectAppExport('OTP Auth'),
    type: FileType.custom,
    allowedExtensions: ['otpauthdb', 'otpauthdp', 'otpauth'],
    showProgressBeforeProcessing: false,
    logger: _logger,
    logMessage: 'Exception while processing OTP Auth import',
    process: (path, progressDialog) =>
        _processOtpAuthFile(context, path, progressDialog),
  );
}

Future<int?> _processOtpAuthFile(
  BuildContext context,
  String path,
  ProgressDialog dialog,
) async {
  final fileBytes = await readPickedImportFileAsBytes(path);
  if (!context.mounted) return null;
  final l10n = context.l10n;
  while (true) {
    if (!context.mounted) return null;
    final password = await promptForImportPassword(
      context,
      title: l10n.passwordForDecryptingExport,
    );
    if (password == null) return null;

    await dialog.show();
    final result = await compute(_parseOtpAuthExport, {
      'fileBytes': fileBytes,
      'password': password,
    });
    if (result['status'] == 'incorrect_password') {
      await dialog.hide();
      if (!context.mounted) return null;
      await showErrorDialog(
        context,
        l10n.incorrectPasswordTitle,
        l10n.pleaseCheckPasswordAndTryAgain,
      );
      continue;
    }

    final codes = (result['otpUris'] as List).cast<String>().map(
      Code.fromOTPAuthUrl,
    );
    return saveImportedCodes(codes);
  }
}

Map<String, Object> _parseOtpAuthExport(Map<String, Object> params) {
  try {
    final codes = parseOtpAuthExport(
      params['fileBytes'] as Uint8List,
      password: params['password'] as String,
    );
    return {
      'status': 'ok',
      'otpUris': codes.map((code) => code.rawData).toList(),
    };
  } on IncorrectOtpAuthPasswordException {
    return {'status': 'incorrect_password'};
  }
}
