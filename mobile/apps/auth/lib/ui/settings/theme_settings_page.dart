import 'package:ente_auth/app/view/app.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_item.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_page_scaffold.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_lock_screen/ui/app_lock.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

class ThemeSettingsPage extends StatefulWidget {
  const ThemeSettingsPage({super.key});

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.componentColors;
    final currentThemeMode = App.themeModeOf(context);

    return AuthSettingsPageScaffold(
      title: l10n.theme,
      children: [
        MenuGroupComponent(
          showDividers: true,
          dividerPadding: const EdgeInsets.only(left: 68),
          items: [
            _themeItem(
              label: l10n.systemTheme,
              icon: HugeIcons.strokeRoundedSmartPhone01,
              mode: ThemeMode.system,
              currentMode: currentThemeMode,
              checkColor: colors.primary,
            ),
            _themeItem(
              label: l10n.lightTheme,
              icon: HugeIcons.strokeRoundedSun03,
              mode: ThemeMode.light,
              currentMode: currentThemeMode,
              checkColor: colors.primary,
            ),
            _themeItem(
              label: l10n.darkTheme,
              icon: HugeIcons.strokeRoundedMoon02,
              mode: ThemeMode.dark,
              currentMode: currentThemeMode,
              checkColor: colors.primary,
            ),
          ],
        ),
      ],
    );
  }

  Widget _themeItem({
    required String label,
    required List<List<dynamic>> icon,
    required ThemeMode mode,
    required ThemeMode currentMode,
    required Color checkColor,
  }) {
    return AuthSettingsItem(
      title: label,
      icon: icon,
      showChevron: false,
      trailing: currentMode == mode
          ? Icon(Icons.check, color: checkColor)
          : null,
      onTap: () => _setTheme(mode),
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
