import "package:adaptive_theme/adaptive_theme.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/settings/theme_selector.dart";
import "package:flutter/material.dart";

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
    final l10n = context.strings;
    return SettingsPageScaffold(
      title: l10n.theme,
      children: [
        ThemeSelector(
          currentMode: currentThemeMode,
          systemMode: AdaptiveThemeMode.system,
          lightMode: AdaptiveThemeMode.light,
          darkMode: AdaptiveThemeMode.dark,
          onChanged: _setTheme,
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
