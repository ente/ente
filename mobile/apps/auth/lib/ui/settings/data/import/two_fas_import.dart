import 'dart:convert';
import 'dart:typed_data';

import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/models/code_display.dart';
import 'package:ente_auth/ui/settings/data/import/import_file_cleanup.dart';
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_ui/components/progress_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:pointycastle/export.dart';

Future<void> show2FasImportInstruction(BuildContext context) async {
  final l10n = context.l10n;
  await showFileImportInstruction(
    context: context,
    title: "2FAS Authenticator",
    body: l10n.import2FasGuide,
    actionLabel: l10n.importSelectAppExport("2FAS Authenticator"),
    semanticsIdentifier: 'auth_import_instruction_two_fas',
    onImport: () => _pick2FasFile(context),
  );
}

Future<void> _pick2FasFile(BuildContext context) async {
  await pickAndProcessImportFile(
    context: context,
    dialogTitle: context.l10n.importSelectJsonFile,
    showProgressBeforeProcessing: false,
    logger: Logger('2FASImport'),
    logMessage: 'Exception while processing 2FAS import',
    process: (path, progressDialog) =>
        _process2FasExportFile(context, path, progressDialog),
  );
}

Future<int?> _process2FasExportFile(
  BuildContext context,
  String path,
  final ProgressDialog dialog,
) async {
  final jsonString = await readPickedImportFileAsString(path);
  final decodedJson = jsonDecode(jsonString);
  int version = (decodedJson['schemaVersion'] ?? 0) as int;
  if (version != 3 && version != 4) {
    if (!context.mounted) return null;
    await dialog.hide();
    if (!context.mounted) return null;
    // todo: extract strings for l10n. Use same naming format as in aegis
    // to avoid duplicate translation efforts.
    await showErrorDialog(
      context,
      'Unsupported format: $version',
      version == 0
          ? "The selected file is not a valid 2FAS Authenticator export."
          : "Sorry, the app doesn't support this version of 2FAS Authenticator export",
    );
    return null;
  }
  final groupIdToName = {};
  var groups = decodedJson['groups'];
  if (groups != null) {
    for (var group in groups) {
      groupIdToName[group['id']] = group['name'];
    }
  }

  var decodedServices = decodedJson['services'];
  // https://github.com/twofas/2fas-android/blob/e97f1a1040eafaed6d5284d54d33403dff215886/data/services/src/main/java/com/twofasapp/data/services/domain/BackupContent.kt#L39
  final isEncrypted = decodedJson['reference'] != null;
  if (isEncrypted) {
    if (!context.mounted) return null;
    String? password;
    try {
      password = await promptForImportPassword(
        context,
        title: context.l10n.enterPasswordToDecrypt2FASBackup,
      );
      if (password == null) {
        await dialog.hide();
        return null;
      }
      await dialog.show();
      final content = decrypt2FasVault(decodedJson, password: password);
      decodedServices = jsonDecode(content);
    } catch (e, s) {
      Logger("2FASImport").warning("exception while decrypting  backup", e, s);
      await dialog.hide();
      if (password != null) {
        if (!context.mounted) return null;
        await showErrorDialog(
          context,
          context.l10n.failedToDecrypt2FASExport,
          context.l10n.pleaseCheckPasswordAndTryAgain,
        );
      }
      return null;
    }
  } else {
    await dialog.show();
  }
  final parsedCodes = <Code>[];
  for (var item in decodedServices) {
    var kind = item['otp']['tokenType'];
    var account = item['otp']['account'] ?? '';
    var issuer = item['otp']['issuer'];
    if (issuer == null || (issuer as String).isEmpty) {
      issuer = item['name'] ?? '';
    }
    final String? groupID = item['groupId'];
    var algorithm = item['otp']['algorithm'];
    var secret = item['secret'];
    var timer = item['otp']['period'];
    var digits = item['otp']['digits'];
    var counter = item['otp']['counter'];

    Code code = Code.fromOTPAuthUrl(
      buildImportOtpUri(
        kind: kind,
        issuer: issuer,
        account: account,
        secret: secret,
        algorithm: algorithm,
        digits: digits,
        period: timer,
        counter: counter,
      ),
    );
    if (groupID != null && groupIdToName.containsKey(groupID)) {
      code = code.copyWith(
        display: CodeDisplay(tags: [groupIdToName[groupID]]),
      );
    }
    parsedCodes.add(code);
  }

  return saveImportedCodes(parsedCodes);
}

String decrypt2FasVault(dynamic data, {required String password}) {
  int iterationCount = 10000;
  int keySize = 256;
  final String encryptedServices = data["servicesEncrypted"];
  var split = encryptedServices.split(":");
  final encryptedData = base64.decode(split[0]);
  final salt = base64.decode(split[1]);
  final iv = base64.decode(split[2]);
  // derive 256 key using PBKDF2WithHmacSHA256 and 10000 iterations and above salt
  final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64));
  final params = Pbkdf2Parameters(salt, iterationCount, keySize ~/ 8);
  pbkdf2.init(params);
  Uint8List key = Uint8List(keySize ~/ 8);
  pbkdf2.deriveKey(Uint8List.fromList(utf8.encode(password)), 0, key, 0);
  final decrypted = decrypt(key, iv, encryptedData);
  final utf8Decode = utf8.decode(decrypted);
  return utf8Decode;
}

Uint8List decrypt(Uint8List key, Uint8List iv, Uint8List data) {
  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(KeyParameter(key), 128, iv, Uint8List.fromList(<int>[])),
    );

  final dbBytes = cipher.process(data);
  return dbBytes;
}
