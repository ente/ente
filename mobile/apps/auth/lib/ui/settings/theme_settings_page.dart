import 'package:ente_auth/app/view/app.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_page_scaffold.dart';
import 'package:ente_lock_screen/ui/app_lock.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/settings/theme_selector.dart';
import 'package:flutter/material.dart';

class ThemeSettingsPage extends StatefulWidget {
  const ThemeSettingsPage({super.key});

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;
    final currentThemeMode = App.themeModeOf(context);

    return AuthSettingsPageScaffold(
      title: l10n.theme,
      children: [
        ThemeSelector(
          currentMode: currentThemeMode,
          systemMode: ThemeMode.system,
          lightMode: ThemeMode.light,
          darkMode: ThemeMode.dark,
          onChanged: _setTheme,
        ),
      ],
    );
  }

  Future<void> _setTheme(ThemeMode themeMode) async {
    final appLock = AppLock.of(context);
    await App.setThemeMode(context, themeMode);
    appLock?.setThemeMode(themeMode);
    if (mounted) {
      setState(() {});
    }
  }
}
