import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/pages/language_selector_page.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/app.dart";
import "package:locker/core/locale.dart";

class GeneralSettingsPage extends StatelessWidget {
  const GeneralSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;

    return SettingsPageScaffold(
      title: l10n.general,
      children: [
        SettingsItem(
          title: l10n.selectLanguage,
          icon: HugeIcons.strokeRoundedLanguageSquare,
          onTap: () => _onLanguageTapped(context),
        ),
      ],
    );
  }

  void _onLanguageTapped(BuildContext context) {
    final currentLocale = Localizations.localeOf(context);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            LanguageSelectorPage(appSupportedLocales, (locale) {
              App.setLocale(context, locale);
              // ignore: unawaited_futures
              setLocale(locale);
            }, currentLocale),
      ),
    );
  }
}
