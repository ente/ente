import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_item.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_page_scaffold.dart';
import 'package:ente_auth/ui/settings/data/local_backup/local_backup_experience.dart';
import 'package:ente_components/ente_components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class LocalBackupSettingsPage extends StatelessWidget {
  const LocalBackupSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LocalBackupExperience(
      builder: (context, controller) {
        final l10n = context.l10n;
        return Semantics(
          identifier: 'auth_local_backup_settings',
          child: AuthSettingsPageScaffold(
            title: l10n.localBackupSettingsTitle,
            children: controller.hasLoaded
                ? _settings(context, controller)
                : const [
                    Padding(
                      padding: EdgeInsets.all(Spacing.xxl),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ],
          ),
        );
      },
    );
  }

  List<Widget> _settings(
    BuildContext context,
    LocalBackupExperienceController controller,
  ) {
    final l10n = context.l10n;
    return [
      MenuGroupComponent(
        items: [
          AuthSettingsItem(
            title: l10n.enableAutomaticBackups,
            showChevron: false,
            trailing: Semantics(
              identifier: 'auth_local_backup_toggle',
              child: ToggleSwitchComponent.async(
                value: () => controller.isBackupEnabled,
                onChanged: () =>
                    controller.toggleBackup(!controller.isBackupEnabled),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: Spacing.sm),
      _Description(l10n.localBackupDailyManualCopy),
      if (controller.isBackupEnabled) ...[
        const SizedBox(height: Spacing.xl),
        MenuGroupComponent(
          showDividers: true,
          dividerPadding: const EdgeInsets.only(left: Spacing.lg),
          items: [
            FutureBuilder<bool>(
              future: controller.hasPasswordConfigured(),
              builder: (context, snapshot) {
                final title = snapshot.data == true
                    ? l10n.updateBackupPassword
                    : l10n.setBackupPassword;
                return AuthSettingsItem(
                  title: title,
                  semanticsIdentifier: 'auth_local_backup_password',
                  onTap: () => controller.updatePassword(context),
                );
              },
            ),
            AuthSettingsItem(
              title: l10n.setBackupFolder,
              subtitle: _locationDescription(context, controller),
              semanticsIdentifier: 'auth_local_backup_folder',
              onTap: controller.changeLocation,
            ),
            AuthSettingsItem(
              title: l10n.createBackupNow,
              semanticsIdentifier: 'auth_local_backup_create_now',
              showOnlyLoadingState: true,
              onTap: controller.isManualBackupRunning
                  ? null
                  : controller.runManualBackup,
            ),
          ],
        ),
      ] else if (kDebugMode) ...[
        const SizedBox(height: Spacing.xl),
        MenuGroupComponent(
          showDividers: true,
          dividerPadding: const EdgeInsets.only(left: Spacing.lg),
          items: [
            AuthSettingsItem(
              title: l10n.clearBackupFolder,
              showChevron: false,
              showOnlyLoadingState: true,
              onTap: controller.resetBackupLocation,
            ),
            AuthSettingsItem(
              title: l10n.clearBackupPassword,
              showChevron: false,
              showOnlyLoadingState: true,
              onTap: controller.clearBackupPassword,
            ),
          ],
        ),
      ],
    ];
  }

  String _locationDescription(
    BuildContext context,
    LocalBackupExperienceController controller,
  ) {
    final l10n = context.l10n;
    final location = controller.backupPath ?? controller.backupTreeUri;
    if (location == null || location.isEmpty) {
      return l10n.selectBackupFolder;
    }
    return '${l10n.backupFolderLabel} ${controller.simplifyPath(location)}';
  }
}

class _Description extends StatelessWidget {
  const _Description(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      child: Text(
        text,
        style: TextStyles.mini.copyWith(
          color: context.componentColors.textLight,
        ),
      ),
    );
  }
}
