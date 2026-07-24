import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_item.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_page_scaffold.dart';
import 'package:ente_auth/ui/settings/data/import/import_service.dart';
import 'package:ente_components/ente_components.dart';
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
        return context.l10n.importTypePlainText;
      case ImportType.encrypted:
        return context.l10n.importTypeEnteEncrypted;
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
      case ImportType.otpAuth:
        return 'OTP Auth';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthSettingsPageScaffold(
      title: context.l10n.importCodes,
      children: [
        MenuGroupComponent(
          showDividers: true,
          items: [
            for (final type in importOptions)
              AuthSettingsItem(
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
