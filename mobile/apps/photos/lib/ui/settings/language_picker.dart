import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/ui/settings/components/settings_page_scaffold.dart";

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
        ItemsWidget(supportedLocales, onLocaleChanged, currentLocale),
        const SizedBox(height: 12),
      ],
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
    currentLocale = widget.currentLocale;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final items = <MenuComponent>[];
    bool foundMatch = false;
    for (Locale locale in widget.supportedLocales) {
      if (currentLocale == locale) {
        foundMatch = true;
      }
      items.add(_menuItemForPicker(locale));
    }
    final debugLocaleText = !foundMatch && kDebugMode
        ? Padding(
            padding: const EdgeInsets.only(bottom: Spacing.md),
            child: Text(
              "(i) Locale : ${currentLocale.toString()}",
              style: TextStyles.mini.copyWith(
                color: context.componentColors.textLight,
              ),
            ),
          )
        : null;

    final children = <Widget>[
      ?debugLocaleText,
      MenuGroupComponent(items: items),
    ];
    return Column(mainAxisSize: MainAxisSize.min, children: children);
  }

  MenuComponent _menuItemForPicker(Locale locale) {
    final isSelected = currentLocale == locale;
    return MenuComponent(
      key: ValueKey(locale.toString()),
      title: getLocaleDisplayName(locale) + (kDebugMode ? ' ($locale)' : ''),
      trailing: isSelected
          ? Icon(Icons.check, color: context.componentColors.primary)
          : null,
      showOnlyLoadingState: true,
      onTap: () async => _selectLocale(locale),
    );
  }

  void _selectLocale(Locale locale) {
    widget.onLocaleChanged(locale);
    currentLocale = locale;
    setState(() {});
  }
}
