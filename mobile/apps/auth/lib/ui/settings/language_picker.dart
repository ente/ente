import 'package:ente_auth/ui/settings/components/auth_settings_page_scaffold.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/language_selector_list.dart';
import 'package:flutter/material.dart';

class LanguageSelectorPage extends StatelessWidget {
  final List<Locale> supportedLocales;
  final ValueChanged<Locale> onLocaleChanged;
  final Locale currentLocale;

  const LanguageSelectorPage(
    this.supportedLocales,
    this.onLocaleChanged,
    this.currentLocale, {
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AuthSettingsPageScaffold(
      title: context.strings.selectLanguage,
      children: [
        LanguageSelectorList(
          supportedLocales,
          onLocaleChanged,
          currentLocale,
          semanticsIdentifier: 'auth_language_list',
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
