import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/app.dart";
import "package:locker/core/locale.dart";
import "package:locker/l10n/l10n.dart";
import "package:locker/ui/settings/components/settings_item.dart";
import "package:locker/ui/settings/components/settings_page_scaffold.dart";
import "package:locker/ui/settings/language_selector_page.dart";

class GeneralSettingsPage extends StatelessWidget {
  const GeneralSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

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
