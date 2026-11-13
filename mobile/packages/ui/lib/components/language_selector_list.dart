import 'package:ente_components/ente_components.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class LanguageSelectorList extends StatefulWidget {
  const LanguageSelectorList(
    this.supportedLocales,
    this.onLocaleChanged,
    this.currentLocale, {
    this.semanticsIdentifier = 'language_selector_list',
    super.key,
  });

  final List<Locale> supportedLocales;
  final ValueChanged<Locale> onLocaleChanged;
  final Locale currentLocale;
  final String semanticsIdentifier;

  @override
  State<LanguageSelectorList> createState() => _LanguageSelectorListState();
}

class _LanguageSelectorListState extends State<LanguageSelectorList> {
  late Locale currentLocale;

  @override
  void initState() {
    currentLocale = _resolveCurrentLocale(
      widget.currentLocale,
      widget.supportedLocales,
    );
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      identifier: widget.semanticsIdentifier,
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
      trailing: selected
          ? Icon(Icons.check, color: context.componentColors.primary)
          : null,
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

Locale _resolveCurrentLocale(Locale current, List<Locale> supported) {
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
