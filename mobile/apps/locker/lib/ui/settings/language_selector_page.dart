import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:locker/l10n/l10n.dart";
import "package:locker/ui/settings/components/settings_item.dart";
import "package:locker/ui/settings/components/settings_page_scaffold.dart";

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
    return SettingsPageScaffold(
      title: context.l10n.selectLanguage,
      children: [
        _LanguageItemsWidget(supportedLocales, onLocaleChanged, currentLocale),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _LanguageItemsWidget extends StatefulWidget {
  final List<Locale> supportedLocales;
  final ValueChanged<Locale> onLocaleChanged;
  final Locale currentLocale;

  const _LanguageItemsWidget(
    this.supportedLocales,
    this.onLocaleChanged,
    this.currentLocale,
  );

  @override
  State<_LanguageItemsWidget> createState() => _LanguageItemsWidgetState();
}

class _LanguageItemsWidgetState extends State<_LanguageItemsWidget> {
  late Locale currentLocale;

  @override
  void initState() {
    currentLocale = widget.currentLocale;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MenuGroupComponent(
      items: [
        for (final locale in widget.supportedLocales)
          _menuItemForPicker(locale),
      ],
    );
  }

  Widget _menuItemForPicker(Locale locale) {
    return SettingsItem(
      key: ValueKey(locale.toString()),
      title: getLocaleDisplayName(locale) + (kDebugMode ? ' ($locale)' : ''),
      showChevron: false,
      trailing: currentLocale == locale
          ? Icon(Icons.check, color: context.componentColors.primary)
          : null,
      showOnlyLoadingState: true,
      onTap: () async {
        widget.onLocaleChanged(locale);
        currentLocale = locale;
        setState(() {});
      },
    );
  }
}
