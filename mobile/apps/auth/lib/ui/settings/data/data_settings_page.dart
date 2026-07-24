import 'dart:async';

import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/services/deduplication_service.dart';
import 'package:ente_auth/services/flagservice.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_item.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_navigation.dart';
import 'package:ente_auth/ui/settings/components/auth_settings_page_scaffold.dart';
import 'package:ente_auth/ui/settings/data/duplicate_code_page.dart';
import 'package:ente_auth/ui/settings/data/export_widget.dart';
import 'package:ente_auth/ui/settings/data/import_page.dart';
import 'package:ente_auth/ui/settings/data/local_backup_settings_page.dart';
import 'package:ente_auth/utils/dialog_util.dart';
import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

class DataSettingsPage extends StatelessWidget {
  const DataSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AuthSettingsPageScaffold(
      title: l10n.data,
      children: [
        AuthSettingsItem(
          title: l10n.importCodes,
          icon: HugeIcons.strokeRoundedFileImport,
          onTap: () => _openImportCodes(context),
        ),
        const SizedBox(height: Spacing.sm),
        AuthSettingsItem(
          title: l10n.exportCodes,
          icon: HugeIcons.strokeRoundedFileExport,
          showOnlyLoadingState: true,
          onTap: () => handleExportClick(context),
        ),
        const SizedBox(height: Spacing.sm),
        AuthSettingsItem(
          title: l10n.duplicateCodes,
          icon: HugeIcons.strokeRoundedCopy01,
          showOnlyLoadingState: true,
          onTap: () => _openDuplicateCodes(context),
        ),
        if (FeatureFlagService.isLocalBackupEnabled()) ...[
          const SizedBox(height: Spacing.sm),
          AuthSettingsItem(
            title: l10n.localBackupSidebarTitle,
            icon: HugeIcons.strokeRoundedHardDrive,
            onTap: () =>
                pushAuthSettingsPage(context, const LocalBackupSettingsPage()),
          ),
        ],
      ],
    );
  }

  Future<void> _openImportCodes(BuildContext context) async {
    final completed = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const ImportCodePage()));
    if (completed == true && context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _openDuplicateCodes(BuildContext context) async {
    final l10n = context.l10n;
    final duplicateCodes = await DeduplicationService.instance
        .getDuplicateCodes();
    if (!context.mounted) return;
    if (duplicateCodes.isEmpty) {
      unawaited(
        showChoiceDialog(
          context,
          title: l10n.noDuplicates,
          firstButtonLabel: l10n.ok,
          secondButtonLabel: null,
          body: l10n.youveNoDuplicateCodesThatCanBeCleared,
        ),
      );
      return;
    }
    await pushAuthSettingsPage(
      context,
      DuplicateCodePage(duplicateCodes: duplicateCodes),
    );
  }
}
