import 'package:ente_auth/ui/settings/components/auth_settings_page_scaffold.dart';
import 'package:ente_auth/ui/settings/data/import/import_service.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';

enum ImportType {
  plainText,
  encrypted,
  ravio,
  googleAuthenticator,
  aegis,
  twoFas,
  bitwarden,
  lastpass,
  proton,
  andOTP,
  openAuthenticator,
  otpAuth,
}

class ImportCodePage extends StatelessWidget {
  const ImportCodePage({super.key});

  static const List<ImportType> importOptions = [
    ImportType.plainText,
    ImportType.encrypted,
    ImportType.twoFas,
    ImportType.aegis,
    ImportType.andOTP,
    ImportType.openAuthenticator,
    ImportType.bitwarden,
    ImportType.googleAuthenticator,
    ImportType.proton,
    ImportType.ravio,
    ImportType.lastpass,
    ImportType.otpAuth,
  ];

  String getTitle(BuildContext context, ImportType type) {
    switch (type) {
      case ImportType.plainText:
        return context.strings.plainText;
      case ImportType.encrypted:
        return context.strings.importTypeEnteEncrypted;
      case ImportType.ravio:
        return 'Raivo OTP';
      case ImportType.googleAuthenticator:
        return 'Google Authenticator';
      case ImportType.aegis:
        return 'Aegis Authenticator';
      case ImportType.twoFas:
        return '2FAS Authenticator';
      case ImportType.bitwarden:
        return 'Bitwarden';
      case ImportType.lastpass:
        return 'LastPass Authenticator';
      case ImportType.proton:
        return 'Proton Authenticator';
      case ImportType.andOTP:
        return 'andOTP';
      case ImportType.openAuthenticator:
        return context.strings.importTypeOpenAuthenticator;
      case ImportType.otpAuth:
        return 'OTP Auth';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthSettingsPageScaffold(
      title: context.strings.importCodes,
      children: [
        MenuGroupComponent(
          showDividers: true,
          items: [
            for (final type in importOptions)
              SettingsItem(
                title: getTitle(context, type),
                semanticsIdentifier: 'auth_import_${type.name}',
                onTap: () => _import(context, type),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _import(BuildContext context, ImportType type) async {
    final completed = await ImportService().initiateImport(context, type);
    if (completed && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }
}
