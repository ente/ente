import "dart:io";

import "package:adaptive_theme/adaptive_theme.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/settings/theme_selector.dart";
import "package:ente_ui/pages/language_selector_page.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/app.dart";
import "package:photos/locale.dart";
import "package:photos/ui/settings/app_icon_selection_screen.dart";
import "package:photos/ui/settings/gallery_settings_screen.dart";

class AppearanceSettingsPage extends StatefulWidget {
  const AppearanceSettingsPage({super.key});

  @override
  State<AppearanceSettingsPage> createState() => _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<AppearanceSettingsPage> {
  AdaptiveThemeMode? _currentThemeMode;

  @override
  void initState() {
    super.initState();
    AdaptiveTheme.getThemeMode().then((value) {
      _currentThemeMode = value ?? AdaptiveThemeMode.system;
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return SettingsPageScaffold(
      title: l10n.appearance,
      children: [
        if (Platform.isAndroid || kDebugMode) ...[
          SettingsItem(
            title: l10n.theme,
            icon: isDarkMode
                ? HugeIcons.strokeRoundedMoon02
                : HugeIcons.strokeRoundedSun03,
            onTap: () async => _showThemePicker(context),
          ),
          const SizedBox(height: 8),
        ],
        SettingsItem(
          title: context.strings.appIcon,
          icon: HugeIcons.strokeRoundedImage02,
          onTap: () async {
            await routeToPage(context, const AppIconSelectionScreen());
          },
        ),
        const SizedBox(height: 8),
        SettingsItem(
          title: l10n.language,
          icon: HugeIcons.strokeRoundedTranslation,
          onTap: () async => _onLanguageTap(context),
        ),
        const SizedBox(height: 8),
        SettingsItem(
          title: l10n.gallery,
          icon: HugeIcons.strokeRoundedImage01,
          onTap: () async {
            await routeToPage(
              context,
              const GallerySettingsScreen(fromGalleryLayoutSettingsCTA: false),
            );
          },
        ),
      ],
    );
  }

  Future<void> _showThemePicker(BuildContext context) async {
    await showBottomSheetComponent<void>(
      context: context,
      builder: (context) => _ThemePickerSheet(
        currentThemeMode: _currentThemeMode,
        onThemeChanged: (themeMode) {
          AdaptiveTheme.of(context).setThemeMode(themeMode);
          setState(() {
            _currentThemeMode = themeMode;
          });
        },
      ),
    );
  }

  Future<void> _onLanguageTap(BuildContext context) async {
    final locale = (await getLocale())!;
    if (!context.mounted) return;
    await routeToPage(
      context,
      LanguageSelectorPage(appSupportedLocales, (locale) async {
        await setLocale(locale);
        if (!context.mounted) return;
        EnteApp.setLocale(context, locale);
      }, locale),
    );
  }
}

class _ThemePickerSheet extends StatelessWidget {
  const _ThemePickerSheet({
    required this.currentThemeMode,
    required this.onThemeChanged,
  });

  final AdaptiveThemeMode? currentThemeMode;
  final ValueChanged<AdaptiveThemeMode> onThemeChanged;

  @override
  Widget build(BuildContext context) {
    return BottomSheetComponent(
      title: context.strings.theme,
      showCloseButton: false,
      content: ThemeSelector(
        currentMode: currentThemeMode,
        systemMode: AdaptiveThemeMode.system,
        lightMode: AdaptiveThemeMode.light,
        darkMode: AdaptiveThemeMode.dark,
        onChanged: (themeMode) => _selectTheme(context, themeMode),
      ),
    );
  }

  void _selectTheme(BuildContext context, AdaptiveThemeMode themeMode) {
    onThemeChanged(themeMode);
    Navigator.pop(context);
  }
}
