import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/language_selector_list.dart';
import 'package:flutter/material.dart';

class LanguageSelectorPage extends StatelessWidget {
  const LanguageSelectorPage(
    this.supportedLocales,
    this.onLocaleChanged,
    this.currentLocale, {
    super.key,
  });

  final List<Locale> supportedLocales;
  final ValueChanged<Locale> onLocaleChanged;
  final Locale currentLocale;

  @override
  Widget build(BuildContext context) {
    return SettingsPageScaffold(
      title: context.strings.selectLanguage,
      children: [
        LanguageSelectorList(supportedLocales, onLocaleChanged, currentLocale),
        const SizedBox(height: 24),
      ],
    );
  }
}
