import "dart:io";

import "package:adaptive_theme/adaptive_theme.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/app.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/ui/settings/app_icon_selection_screen.dart";
import "package:photos/ui/settings/components/settings_item.dart";
import "package:photos/ui/settings/components/settings_page_scaffold.dart";
import "package:photos/ui/settings/gallery_settings_screen.dart";
import "package:photos/ui/settings/language_picker.dart";

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
    final l10n = AppLocalizations.of(context);
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
          title: context.l10n.appIcon,
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
  final AdaptiveThemeMode? currentThemeMode;
  final Function(AdaptiveThemeMode) onThemeChanged;

  const _ThemePickerSheet({
    required this.currentThemeMode,
    required this.onThemeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return BottomSheetComponent(
      title: AppLocalizations.of(context).theme,
      showCloseButton: false,
      content: MenuGroupComponent(
        items: [
          _themeOption(
            context,
            title: AppLocalizations.of(context).lightTheme,
            isSelected: currentThemeMode == AdaptiveThemeMode.light,
            onTap: () => _selectTheme(context, AdaptiveThemeMode.light),
          ),
          _themeOption(
            context,
            title: AppLocalizations.of(context).darkTheme,
            isSelected: currentThemeMode == AdaptiveThemeMode.dark,
            onTap: () => _selectTheme(context, AdaptiveThemeMode.dark),
          ),
          _themeOption(
            context,
            title: AppLocalizations.of(context).systemTheme,
            isSelected: currentThemeMode == AdaptiveThemeMode.system,
            onTap: () => _selectTheme(context, AdaptiveThemeMode.system),
          ),
        ],
      ),
    );
  }

  MenuComponent _themeOption(
    BuildContext context, {
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return MenuComponent(
      title: title,
      trailing: isSelected
          ? HugeIcon(
              icon: HugeIcons.strokeRoundedTick02,
              color: context.componentColors.primary,
              size: IconSizes.medium,
            )
          : null,
      onTap: onTap,
    );
  }

  void _selectTheme(BuildContext context, AdaptiveThemeMode themeMode) {
    onThemeChanged(themeMode);
    Navigator.pop(context);
  }
}
