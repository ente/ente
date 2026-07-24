import 'dart:io';

import 'package:ente_auth/app/view/app.dart';
import 'package:ente_auth/events/icons_changed_event.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/locale.dart';
import 'package:ente_auth/services/preference_service.dart';
import 'package:ente_auth/ui/settings/app_icon_selection_screen.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_item.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_navigation.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_page_scaffold.dart';
import 'package:ente_auth/ui/settings/language_picker.dart';
import 'package:ente_auth/utils/toast_util.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_events/event_bus.dart';
import 'package:ente_logging/logging.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

class GeneralSettingsPage extends StatelessWidget {
  const GeneralSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AuthSettingsPageScaffold(
      title: l10n.general,
      children: [
        AuthSettingsItem(
          title: l10n.language,
          icon: HugeIcons.strokeRoundedLanguageSquare,
          onTap: () => _openLanguage(context),
        ),
        if (Platform.isIOS || Platform.isAndroid) ...[
          const SizedBox(height: Spacing.sm),
          AuthSettingsItem(
            title: l10n.appIcon,
            icon: HugeIcons.strokeRoundedImage01,
            onTap: () =>
                pushAuthSettingsPage(context, const AppIconSelectionScreen()),
          ),
        ],
        const SizedBox(height: Spacing.lg),
        MenuGroupComponent(
          showDividers: true,
          dividerPadding: const EdgeInsets.only(left: Spacing.lg),
          items: [
            _toggleItem(
              title: l10n.showLargeIcons,
              value: PreferenceService.instance.shouldShowLargeIcons,
              onChanged: () => PreferenceService.instance.setShowLargeIcons(
                !PreferenceService.instance.shouldShowLargeIcons(),
              ),
            ),
            _toggleItem(
              title: l10n.compactMode,
              value: PreferenceService.instance.isCompactMode,
              onChanged: () async {
                await PreferenceService.instance.setCompactMode(
                  !PreferenceService.instance.isCompactMode(),
                );
                Bus.instance.fire(IconsChangedEvent());
              },
            ),
            _toggleItem(
              title: l10n.shouldHideCode,
              value: PreferenceService.instance.shouldHideCodes,
              onChanged: () async {
                await PreferenceService.instance.setHideCodes(
                  !PreferenceService.instance.shouldHideCodes(),
                );
                if (PreferenceService.instance.shouldHideCodes() &&
                    context.mounted) {
                  showToast(context, l10n.doubleTapToViewHiddenCode);
                }
              },
            ),
            _toggleItem(
              title: l10n.focusOnSearchBar,
              value: PreferenceService.instance.shouldAutoFocusOnSearchBar,
              onChanged: () =>
                  PreferenceService.instance.setAutoFocusOnSearchBar(
                    !PreferenceService.instance.shouldAutoFocusOnSearchBar(),
                  ),
            ),
            if (Platform.isAndroid)
              _toggleItem(
                title: l10n.minimizeAppOnCopy,
                value: PreferenceService.instance.shouldMinimizeOnCopy,
                onChanged: () =>
                    PreferenceService.instance.setShouldMinimizeOnCopy(
                      !PreferenceService.instance.shouldMinimizeOnCopy(),
                    ),
              ),
            if (PlatformDetector.isDesktop())
              _toggleItem(
                title: l10n.minimizeToTrayOnClose,
                value: PreferenceService.instance.shouldMinimizeToTrayOnClose,
                onChanged: () =>
                    PreferenceService.instance.setShouldMinimizeToTrayOnClose(
                      !PreferenceService.instance.shouldMinimizeToTrayOnClose(),
                    ),
              ),
            _toggleItem(
              title: l10n.crashAndErrorReporting,
              value: SuperLogging.shouldReportErrors,
              onChanged: () => SuperLogging.setShouldReportErrors(
                !SuperLogging.shouldReportErrors(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  AuthSettingsItem _toggleItem({
    required String title,
    required ValueGetter<bool> value,
    required Future<void> Function() onChanged,
  }) {
    return AuthSettingsItem(
      title: title,
      showChevron: false,
      trailing: ToggleSwitchComponent.async(value: value, onChanged: onChanged),
    );
  }

  Future<void> _openLanguage(BuildContext context) async {
    final locale = (await getLocale())!;
    if (!context.mounted) return;
    await pushAuthSettingsPage(
      context,
      LanguageSelectorPage(appSupportedLocales, (newLocale) async {
        await setLocale(newLocale);
        if (context.mounted) {
          App.setLocale(context, newLocale);
        }
      }, locale),
    );
  }
}
