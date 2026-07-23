import "package:adaptive_theme/adaptive_theme.dart";
import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/l10n/l10n.dart";
import "package:locker/ui/settings/components/settings_item.dart";
import "package:locker/ui/settings/components/settings_page_scaffold.dart";

class ThemeSettingsPage extends StatefulWidget {
  const ThemeSettingsPage({super.key});

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  AdaptiveThemeMode? currentThemeMode;

  @override
  void initState() {
    super.initState();
    AdaptiveTheme.getThemeMode().then((value) {
      currentThemeMode = value ?? AdaptiveThemeMode.system;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.componentColors;

    return SettingsPageScaffold(
      title: l10n.theme,
      children: [
        MenuGroupComponent(
          items: [
            SettingsItem(
              title: l10n.systemTheme,
              icon: HugeIcons.strokeRoundedSmartPhone01,
              showChevron: false,
              trailing: currentThemeMode == AdaptiveThemeMode.system
                  ? Icon(Icons.check, color: colors.primary)
                  : null,
              onTap: () => _setTheme(AdaptiveThemeMode.system),
            ),
            SettingsItem(
              title: l10n.lightTheme,
              icon: HugeIcons.strokeRoundedSun03,
              showChevron: false,
              trailing: currentThemeMode == AdaptiveThemeMode.light
                  ? Icon(Icons.check, color: colors.primary)
                  : null,
              onTap: () => _setTheme(AdaptiveThemeMode.light),
            ),
            SettingsItem(
              title: l10n.darkTheme,
              icon: HugeIcons.strokeRoundedMoon02,
              showChevron: false,
              trailing: currentThemeMode == AdaptiveThemeMode.dark
                  ? Icon(Icons.check, color: colors.primary)
                  : null,
              onTap: () => _setTheme(AdaptiveThemeMode.dark),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _setTheme(AdaptiveThemeMode themeMode) async {
    AdaptiveTheme.of(context).setThemeMode(themeMode);
    currentThemeMode = themeMode;
    if (mounted) {
      setState(() {});
    }
  }
}
