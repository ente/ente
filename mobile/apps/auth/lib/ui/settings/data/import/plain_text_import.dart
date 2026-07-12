import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ente_auth/ente_theme_data.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/services/authenticator_service.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:ente_auth/ui/settings/data/import/import_file_cleanup.dart';
import 'package:ente_auth/ui/settings/data/import/import_success.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

final _logger = Logger('PlainText');

class PlainTextImport extends StatelessWidget {
  const PlainTextImport({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Column(
      children: [
        Text(l10n.importInstruction),
        const SizedBox(height: 20),
        Container(
          color: Theme.of(context).colorScheme.gNavBackgroundColor,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              "otpauth://totp/provider.com:you@email.com?secret=YOUR_SECRET",
              style: TextStyle(
                fontFeatures: const [FontFeature.tabularFigures()],
                fontFamily: Platform.isIOS ? "Courier" : "monospace",
                fontSize: 13,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(l10n.importCodeDelimiterInfo),
      ],
    );
  }
}

Future<void> showImportInstructionDialog(BuildContext context) async {
  final l10n = context.l10n;
  final AlertDialog alert = AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    title: Text(
      l10n.importCodes,
      style: Theme.of(context).textTheme.titleLarge,
    ),
    content: const SingleChildScrollView(child: PlainTextImport()),
    actions: [
      TextButton(
        child: Text(l10n.cancel, style: const TextStyle(color: Colors.red)),
        onPressed: () {
          Navigator.of(context, rootNavigator: true).pop('dialog');
        },
      ),
      TextButton(
        child: Text(l10n.selectFile),
        onPressed: () {
          Navigator.of(context, rootNavigator: true).pop('dialog');
          _pickImportFile(context);
        },
      ),
    ],
  );

  return showDialog(
    context: context,
    builder: (BuildContext context) {
      return alert;
    },
    barrierColor: Colors.black12,
  );
}

Future<void> _pickImportFile(BuildContext context) async {
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
    final parsedCodes = [];
    final codes = await readPickedImportFileAsString(result.files.single.path!);

    if (codes.startsWith('otpauth://')) {
      List<String> splitCodes = codes.split(",");
      if (splitCodes.length == 1) {
        splitCodes = const LineSplitter().convert(codes);
      }
      for (final code in splitCodes) {
        try {
          parsedCodes.add(Code.fromOTPAuthUrl(code));
        } catch (e) {
          Logger('PlainText').severe("Could not parse code", e);
        }
      }
    } else {
      final decodedCodes = jsonDecode(codes);
      List<Map> splitCodes = List.from(decodedCodes["items"]);

      for (final code in splitCodes) {
        try {
          parsedCodes.add(Code.fromExportJson(code));
        } catch (e) {
          _logger.severe("Could not parse code", e);
        }
      }
    }

    for (final code in parsedCodes) {
      await CodeStore.instance.addCode(code, shouldSync: false);
    }
    unawaited(AuthenticatorService.instance.onlineSync());
    await progressDialog.hide();
    if (!context.mounted) return;
    await importSuccessDialog(context, parsedCodes.length);
  } catch (e) {
    await progressDialog.hide();
    if (!context.mounted) return;
    if (!context.mounted) return;
    await showErrorDialog(
      context,
      context.l10n.sorry,
      context.l10n.importFailureDesc,
    );
  }
}
