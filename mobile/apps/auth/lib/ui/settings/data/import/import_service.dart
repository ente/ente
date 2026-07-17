import 'package:ente_auth/ui/settings/data/import/aegis_import.dart';
import 'package:ente_auth/ui/settings/data/import/andotp_import.dart';
import 'package:ente_auth/ui/settings/data/import/bitwarden_import.dart';
import 'package:ente_auth/ui/settings/data/import/encrypted_ente_import.dart';
import 'package:ente_auth/ui/settings/data/import/google_auth_import.dart';
import 'package:ente_auth/ui/settings/data/import/lastpass_import.dart';
import 'package:ente_auth/ui/settings/data/import/plain_text_import.dart';
import 'package:ente_auth/ui/settings/data/import/proton_import.dart';
import 'package:ente_auth/ui/settings/data/import/raivo_plain_text_import.dart';
import 'package:ente_auth/ui/settings/data/import/two_fas_import.dart';
import 'package:ente_auth/ui/settings/data/import_page.dart';
import 'package:flutter/cupertino.dart';

class ImportService {
  static final ImportService _instance = ImportService._internal();

  factory ImportService() => _instance;

  ImportService._internal();

  Future<bool> initiateImport(BuildContext context, ImportType type) async {
    switch (type) {
      case ImportType.plainText:
        await showImportInstructionDialog(context);
        return false;
      case ImportType.encrypted:
        await showEncryptedImportInstruction(context);
        return false;
      case ImportType.ravio:
        await showRaivoImportInstruction(context);
        return false;
      case ImportType.googleAuthenticator:
        return showGoogleAuthInstruction(context);
      case ImportType.aegis:
        await showAegisImportInstruction(context);
        return false;
      case ImportType.twoFas:
        await show2FasImportInstruction(context);
        return false;
      case ImportType.bitwarden:
        await showBitwardenImportInstruction(context);
        return false;
      case ImportType.lastpass:
        await showLastpassImportInstruction(context);
        return false;
      case ImportType.proton:
        await showProtonImportInstruction(context);
        return false;
      case ImportType.andOTP:
        await showAndOTPImportInstruction(context);
        return false;
    }
  }
}
