import 'dart:convert';
import 'dart:io';

import 'package:ente_auth/core/configuration.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/export/ente.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/ui/components/buttons/button_widget.dart';
import 'package:ente_auth/ui/components/dialog_widget.dart';
import 'package:ente_auth/ui/components/models/button_type.dart';
import 'package:ente_auth/ui/settings/data/html_export.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_auth/utils/share_utils.dart' as auth_share;
import 'package:ente_auth/utils/toast_util.dart';
import 'package:ente_crypto_api/ente_crypto_api.dart';
import 'package:ente_lock_screen/local_authentication_service.dart';
import 'package:ente_utils/ente_utils.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

Future<void> handleExportClick(BuildContext context) async {
  final result = await showDialogWidget(
    context: context,
    title: context.l10n.selectExportFormat,
    body: context.l10n.exportDialogDesc,
    buttons: [
      ButtonWidget(
        buttonType: ButtonType.primary,
        labelText: context.l10n.encrypted,
        isInAlert: true,
        buttonSize: ButtonSize.large,
        buttonAction: ButtonAction.first,
      ),
      ButtonWidget(
        buttonType: ButtonType.secondary,
        labelText: context.l10n.plainText,
        buttonSize: ButtonSize.large,
        isInAlert: true,
        buttonAction: ButtonAction.second,
      ),
      ButtonWidget(
        buttonType: ButtonType.secondary,
        labelText: context.l10n.plainHTML,
        buttonSize: ButtonSize.large,
        isInAlert: true,
        buttonAction: ButtonAction.third,
      ),
    ],
  );
  if (result?.action != null && result!.action != ButtonAction.cancel) {
    if (!context.mounted) return;
    if (result.action == ButtonAction.first) {
      await _requestForEncryptionPassword(context);
    } else if (result.action == ButtonAction.second) {
      await _showExportWarningDialog(context, "txt");
    } else if (result.action == ButtonAction.third) {
      await _showExportWarningDialog(context, "html");
    }
  }
}

Future<void> _requestForEncryptionPassword(
  BuildContext context, {
  String? password,
}) async {
  final l10n = context.l10n;
  await showTextInputDialog(
    context,
    title: l10n.passwordToEncryptExport,
    submitButtonLabel: l10n.export,
    hintText: l10n.enterPassword,
    isPasswordInput: true,
    alwaysShowSuccessState: false,
    onSubmit: (String password) async {
      if (password.isEmpty || password.length < 4) {
        if (!context.mounted) return;
        showToast(context, "Password must be at least 4 characters long.");
        Future.delayed(const Duration(seconds: 0), () {
          if (!context.mounted) return;
          _requestForEncryptionPassword(context, password: password);
        });
        return;
      }
      if (password.isNotEmpty) {
        if (!context.mounted) return;
        try {
          final kekSalt = CryptoUtil.getSaltToDeriveKey();
          final derivedKeyResult = await CryptoUtil.deriveSensitiveKey(
            utf8.encode(password),
            kekSalt,
          );
          String exportPlainText = await _getAuthDataForExport();
          // Encrypt the key with this derived key
          final encResult = await CryptoUtil.encryptData(
            utf8.encode(exportPlainText),
            derivedKeyResult.key,
          );
          final encContent = CryptoUtil.bin2base64(encResult.encryptedData!);
          final encNonce = CryptoUtil.bin2base64(encResult.header!);
          final EnteAuthExport data = EnteAuthExport(
            version: 1,
            encryptedData: encContent,
            encryptionNonce: encNonce,
            kdfParams: KDFParams(
              memLimit: derivedKeyResult.memLimit,
              opsLimit: derivedKeyResult.opsLimit,
              salt: CryptoUtil.bin2base64(kekSalt),
            ),
          );
          if (!context.mounted) return;
          // get json value of data
          await _exportCodes(
            context,
            jsonEncode(data.toJson()),
            "encrypted",
            "json",
          );
        } catch (e) {
          if (!context.mounted) return;
          showToast(context, "Error while exporting codes.");
        }
      }
    },
  );
}

Future<void> _showExportWarningDialog(BuildContext context, String type) async {
  final result = await showChoiceActionSheet(
    context,
    title: context.l10n.warning,
    body: context.l10n.exportWarningDesc,
    isCritical: true,
    secondButtonLabel: context.l10n.cancel,
    firstButtonLabel: context.l10n.iUnderStand,
  );

  if (result?.action == ButtonAction.first) {
    if (!context.mounted) return;
    if (type == "html") {
      final data = await generateHtml(context);
      if (!context.mounted) return;
      await _exportCodes(context, data, "plainhtml", type);
    } else {
      final data = await _getAuthDataForExport();
      if (!context.mounted) return;
      await _exportCodes(context, data, "plaintext", type);
    }
  }
}

Future<void> _exportCodes(
  BuildContext context,
  String fileContent,
  String exportType,
  String extension,
) async {
  DateTime now = DateTime.now().toUtc();
  String formattedDate = DateFormat('yyyyMMdd-HHmmss').format(now);
  String exportFileName = 'ente-auth-codes-$exportType-$formattedDate';
  final hasAuthenticated = await LocalAuthenticationService.instance
      .requestLocalAuthentication(context, context.l10n.authToExportCodes);
  if (!hasAuthenticated) {
    return;
  }
  if (!context.mounted) return;
  Future.delayed(const Duration(milliseconds: 1200), () async {
    if (!context.mounted) return;
    await auth_share.shareDialog(
      context,
      context.l10n.exportCodes,
      saveAction: () async {
        await FileSaverUtil.saveFile(
          exportFileName,
          extension,
          CryptoUtil.strToBin(fileContent),
          MimeType.text,
        );
      },
      sendAction: () async {
        final codeFile = File(
          "${Configuration.instance.getTempDirectory()}$exportFileName.$extension",
        );
        if (codeFile.existsSync()) {
          await codeFile.delete();
        }
        codeFile.writeAsStringSync(fileContent);
        if (!context.mounted) return;
        final Size size = MediaQuery.of(context).size;
        await SharePlus.instance.share(
          ShareParams(
            files: <XFile>[XFile(codeFile.path, mimeType: 'text/plain')],
            sharePositionOrigin: Rect.fromLTWH(
              0,
              0,
              size.width,
              size.height / 2,
            ),
          ),
        );
        Future.delayed(const Duration(seconds: 30), () async {
          if (codeFile.existsSync()) {
            codeFile.deleteSync();
          }
        });
      },
    );
  });
}

Future<String> _getAuthDataForExport() async {
  final allCodes = await CodeStore.instance.getAllCodes();
  String data = "";
  for (final code in allCodes) {
    if (code.hasError) continue;
    data +=
        "${code.rawData.replaceAll('algorithm=Algorithm.', 'algorithm=').replaceAll(',', '%2C')}\n";
  }

  return data;
}
