import 'dart:convert';
import 'dart:typed_data';

import 'package:convert/convert.dart';
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
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/gcm.dart';
import 'package:pointycastle/key_derivators/scrypt.dart';
import 'package:pointycastle/pointycastle.dart';

Future<void> showAegisImportInstruction(BuildContext context) async {
  final l10n = context.l10n;
  await showFileImportInstruction(
    context: context,
    title: "Aegis Authenticator",
    body: l10n.importAegisGuide,
    actionLabel: l10n.importSelectJsonFile,
    semanticsIdentifier: 'auth_import_instruction_aegis',
    onImport: () => _pickAegisJsonFile(context),
  );
}

Future<void> _pickAegisJsonFile(BuildContext context) async {
  await pickAndProcessImportFile(
    context: context,
    dialogTitle: context.l10n.importSelectJsonFile,
    logger: Logger('AegisImport'),
    logMessage: 'Exception while processing Aegis import',
    process: (path, progressDialog) =>
        _processAegisExportFile(context, path, progressDialog),
  );
}

Future<int?> _processAegisExportFile(
  BuildContext context,
  String path,
  final ProgressDialog dialog,
) async {
  final jsonString = await readPickedImportFileAsString(path);
  final decodedJson = jsonDecode(jsonString);
  final isEncrypted = decodedJson['header']['slots'] != null;
  Map? aegisDB;
  if (isEncrypted) {
    if (!context.mounted) return null;
    await dialog.hide();
    String? password;
    try {
      if (!context.mounted) return null;
      password = await promptForImportPassword(
        context,
        title: context.l10n.enterPasswordToAegisVault,
      );
      if (password == null) {
        await dialog.hide();
        return null;
      }
      await dialog.show();
      final content = decryptAegisVault(decodedJson, password: password);
      aegisDB = jsonDecode(content);
    } catch (e, s) {
      Logger(
        "AegisImport",
      ).warning("exception while decrypting aegis vault", e, s);
      await dialog.hide();
      if (password != null) {
        if (!context.mounted) return null;
        await showErrorDialog(
          context,
          context.l10n.failedToDecryptAegisVault,
          context.l10n.pleaseCheckPasswordAndTryAgain,
        );
      }
      return null;
    }
  } else {
    aegisDB = decodedJson['db'];
  }
  final Map<String, String> groupIDToName = {};
  try {
    if (aegisDB?['groups'] != null) {
      for (var item in aegisDB?['groups']) {
        groupIDToName[item['uuid']] = item['name'];
      }
    }
  } catch (e) {
    Logger("AegisImport").warning("Failed to parse groups", e);
  }

  final parsedCodes = <Code>[];
  for (var item in aegisDB?['entries']) {
    bool isFavorite = item['favorite'] ?? false;
    List<String> tags = [];
    var kind = item['type'];
    var account = Uri.encodeComponent(item['name']);
    var issuer = Uri.encodeComponent(item['issuer']);
    var algorithm = item['info']['algo'];
    var secret = item['info']['secret'];
    var timer = item['info']['period'];
    var digits = item['info']['digits'];

    var counter = item['info']['counter'];
    if (item['groups'] != null) {
      for (var group in item['groups']) {
        if (groupIDToName.containsKey(group)) {
          tags.add(groupIDToName[group]!);
        }
      }
    }
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
    code = code.copyWith(
      display: CodeDisplay(pinned: isFavorite, tags: tags),
    );
    parsedCodes.add(code);
  }

  return saveImportedCodes(parsedCodes);
}

String decryptAegisVault(dynamic data, {required String password}) {
  final header = data["header"];
  final slots = (header["slots"] as List)
      .where((slot) => slot["type"] == 1)
      .toList();

  Uint8List? masterKey;
  for (final slot in slots) {
    final salt = Uint8List.fromList(hex.decode(slot["salt"]));
    final int iterations = slot["n"];
    final int r = slot["r"];
    final int p = slot["p"];
    const int derivedKeyLength = 32;
    final script = Scrypt()
      ..init(ScryptParameters(iterations, r, p, derivedKeyLength, salt));

    final key = script.process(Uint8List.fromList(utf8.encode(password)));

    final params = slot["key_params"];
    final nonce = Uint8List.fromList(hex.decode(params["nonce"]));
    final encryptedKeyWithTag = Uint8List.fromList(
      hex.decode(slot["key"]) + hex.decode(params["tag"]),
    );

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          128,
          nonce,
          Uint8List.fromList(<int>[]),
        ),
      );

    try {
      masterKey = cipher.process(encryptedKeyWithTag);
      break;
    } catch (e) {
      // Ignore decryption failure and continue to next slot
    }
  }

  if (masterKey == null) {
    throw Exception("Unable to decrypt the master key with the given password");
  }

  final content = base64.decode(data["db"]);
  final params = header["params"];
  final nonce = Uint8List.fromList(hex.decode(params["nonce"]));
  final tag = Uint8List.fromList(hex.decode(params["tag"]));
  final cipherTextWithTag = Uint8List.fromList(content + tag);

  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(
        KeyParameter(masterKey),
        128,
        nonce,
        Uint8List.fromList(<int>[]),
      ),
    );

  final dbBytes = cipher.process(cipherTextWithTag);
  return utf8.decode(dbBytes);
}
