import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/settings/about_settings_section.dart";
import "package:ente_ui/utils/toast_util.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/services/update_service.dart";
import "package:locker/ui/settings/app_update_sheet.dart";
import "package:locker/ui/settings/widgets/change_log_sheet.dart";

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;

    return SettingsPageScaffold(
      title: l10n.about,
      children: [
        SettingsItem(
          title: l10n.whatsNew,
          icon: HugeIcons.strokeRoundedParty,
          onTap: () => _openChangeLog(context),
        ),
        const SizedBox(height: Spacing.sm),
        AboutSettingsSection(
          onCheckForUpdates: UpdateService.instance.isIndependent()
              ? () => _onCheckForUpdatesTapped(context)
              : null,
        ),
      ],
    );
  }

  Future<void> _openChangeLog(BuildContext context) async {
    await UpdateService.instance.markChangeLogShown();
    if (context.mounted) {
      await showChangeLogSheet(context);
    }
  }

  Future<void> _onCheckForUpdatesTapped(BuildContext context) async {
    final l10n = context.strings;
    final shouldUpdate = await UpdateService.instance.shouldUpdate();
    final latestVersion = UpdateService.instance.getLatestVersionInfo();
    if (!context.mounted) {
      return;
    }
    if (latestVersion == null) {
      showShortToast(context, l10n.unableToCheckForUpdatesRightNow);
      return;
    }
    if (!shouldUpdate) {
      showShortToast(context, l10n.youAreOnTheLatestVersion);
      return;
    }
    await showAppUpdateSheet(context, latestVersionInfo: latestVersion);
  }
}
