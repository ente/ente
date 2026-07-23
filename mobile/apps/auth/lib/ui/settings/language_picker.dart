import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_page_scaffold.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/foundation.dart';
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
      title: context.l10n.selectLanguage,
      children: [ItemsWidget(supportedLocales, onLocaleChanged, currentLocale)],
    );
  }
}

class ItemsWidget extends StatefulWidget {
  final List<Locale> supportedLocales;
  final ValueChanged<Locale> onLocaleChanged;
  final Locale currentLocale;

  const ItemsWidget(
    this.supportedLocales,
    this.onLocaleChanged,
    this.currentLocale, {
    super.key,
  });

  @override
  State<ItemsWidget> createState() => _ItemsWidgetState();
}

class _ItemsWidgetState extends State<ItemsWidget> {
  late Locale currentLocale;

  @override
  void initState() {
    currentLocale = _resolvedCurrentLocale(
      widget.currentLocale,
      widget.supportedLocales,
    );
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: 'auth_language_list',
      child: MenuGroupComponent(
        showDividers: true,
        dividerPadding: const EdgeInsets.only(left: Spacing.lg),
        items: [
          for (final locale in widget.supportedLocales)
            _menuItemForPicker(locale),
        ],
      ),
    );
  }

  MenuComponent _menuItemForPicker(Locale locale) {
    final selected = currentLocale == locale;
    return MenuComponent(
      key: ValueKey(locale.toString()),
      title: getLocaleDisplayName(locale) + (kDebugMode ? ' ($locale)' : ''),
      selected: selected,
      trailing: RadioComponent(
        selected: selected,
        onChanged: (_) => _selectLocale(locale),
      ),
      showOnlyLoadingState: true,
      onTap: () => _selectLocale(locale),
    );
  }

  void _selectLocale(Locale locale) {
    widget.onLocaleChanged(locale);
    currentLocale = locale;
    setState(() {});
  }
}

Locale _resolvedCurrentLocale(Locale current, List<Locale> supported) {
  if (supported.contains(current)) return current;

  final languageMatches = supported
      .where((locale) => locale.languageCode == current.languageCode)
      .toList();
  if (languageMatches.isEmpty) return current;

  return languageMatches.firstWhere(
    (locale) => locale.countryCode == null,
    orElse: () => languageMatches.first,
  );
}
