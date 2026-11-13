import 'package:ente_auth/services/update_service.dart';
import 'package:ente_auth/ui/settings/app_update_sheet.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_page_scaffold.dart';
import 'package:ente_auth/utils/toast_util.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:ente_ui/components/settings/about_settings_section.dart';
import 'package:flutter/material.dart';

class AboutSettingsPage extends StatelessWidget {
  const AboutSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;
    return AuthSettingsPageScaffold(
      title: l10n.about,
      children: [
        AboutSettingsSection(
          onCheckForUpdates: UpdateService.instance.supportsInAppUpdates()
              ? () => _checkForUpdates(context)
              : null,
        ),
      ],
    );
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    final shouldUpdate = await UpdateService.instance.shouldUpdate();
    final latestVersion = UpdateService.instance.getLatestVersionInfo();
    if (!context.mounted) return;
    if (latestVersion == null) {
      showShortToast(context, context.strings.unableToCheckForUpdatesRightNow);
      return;
    }
    if (!shouldUpdate) {
      showShortToast(context, context.strings.youAreOnTheLatestVersion);
      return;
    }
    await showAppUpdateSheet(context, latestVersionInfo: latestVersion);
  }
}
