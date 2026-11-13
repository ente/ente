import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/ui/common/backup_flow_helper.dart";
import "package:photos/ui/settings/backup/backup_settings_screen.dart";
import "package:photos/ui/settings/backup/backup_status_screen.dart";

class BackupSettingsPage extends StatelessWidget {
  const BackupSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;

    return SettingsPageScaffold(
      title: l10n.backup,
      children: [
        SettingsItem(
          title: l10n.backedUpFolders,
          icon: HugeIcons.strokeRoundedFolder01,
          showOnlyLoadingState: true,
          onTap: () async {
            await handleFolderSelectionBackupFlow(context);
          },
        ),
        const SizedBox(height: 8),
        SettingsItem(
          title: l10n.backupStatus,
          icon: HugeIcons.strokeRoundedCloudSavingDone01,
          showOnlyLoadingState: true,
          onTap: () async {
            await routeToPage(context, const BackupStatusScreen());
          },
        ),
        const SizedBox(height: 8),
        SettingsItem(
          title: l10n.backupSettings,
          icon: HugeIcons.strokeRoundedSettings01,
          showOnlyLoadingState: true,
          onTap: () async {
            await routeToPage(context, const BackupSettingsScreen());
          },
        ),
      ],
    );
  }
}
