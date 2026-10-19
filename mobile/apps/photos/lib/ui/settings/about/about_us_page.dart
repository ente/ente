import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/settings/about_settings_section.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/service_locator.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/notification/update/change_log_page.dart";
import "package:photos/ui/settings/app_update_sheet.dart";

class AboutUsPage extends StatelessWidget {
  const AboutUsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;

    return SettingsPageScaffold(
      title: l10n.about,
      children: [
        SettingsItem(
          title: l10n.whatsNew,
          icon: HugeIcons.strokeRoundedParty,
          showOnlyLoadingState: true,
          onTap: () => showChangeLogSheet(context),
        ),
        const SizedBox(height: Spacing.sm),
        AboutSettingsSection(
          onCheckForUpdates: updateService.isIndependent()
              ? () => _checkForUpdates(context)
              : null,
        ),
      ],
    );
  }

  Future<void> _checkForUpdates(BuildContext context) async {
    final shouldUpdate = await updateService.shouldUpdate();
    final latestVersion = updateService.getLatestVersionInfo();
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
