import "dart:io";

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/sync/local_sync_service.dart";
import "package:photos/services/sync/sync_service.dart";
import "package:photos/services/wake_lock_service.dart";
import "package:photos/ui/common/backup_flow_helper.dart";
import "package:photos/ui/settings/components/settings_page_scaffold.dart";
import "package:photos/utils/dialog_util.dart";

class BackupSettingsScreen extends StatelessWidget {
  const BackupSettingsScreen({super.key});

  static final Debouncer _onlyNewToggleDebouncer = Debouncer(
    const Duration(milliseconds: 500),
    leading: true,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SettingsPageScaffold(
      title: l10n.backupSettings,
      children: [
        _toggleItem(
          context,
          title: l10n.backupOverMobileData,
          value: () => backupSettings.shouldBackupOverMobileData(),
          onChanged: () async {
            final shouldBackupOverMobileData = !backupSettings
                .shouldBackupOverMobileData();
            await backupSettings.setBackupOverMobileData(
              shouldBackupOverMobileData,
            );
            if (shouldBackupOverMobileData) {
              SyncService.instance.sync().ignore();
            }
          },
        ),
        const SizedBox(height: 8),
        _toggleItem(
          context,
          title: l10n.backupVideos,
          value: () => backupSettings.shouldBackupVideos(),
          onChanged: () async {
            final shouldBackupVideos = !backupSettings.shouldBackupVideos();
            await backupSettings.setBackupVideos(shouldBackupVideos);
            if (shouldBackupVideos) {
              SyncService.instance.sync().ignore();
            } else {
              SyncService.instance.onVideoBackupPaused();
            }
          },
        ),
        const SizedBox(height: 8),
        _BackupOnlyNewPhotosToggle(debouncer: _onlyNewToggleDebouncer),
        if (flagService.enableMobMultiPart) ...[
          const SizedBox(height: 8),
          _toggleItem(
            context,
            title: l10n.resumableUploads,
            value: () => localSettings.userEnabledMultiplePart,
            onChanged: () async {
              await localSettings.setUserEnabledMultiplePart(
                !localSettings.userEnabledMultiplePart,
              );
            },
          ),
        ],
        if (endpointConfig.isProduction) ...[
          const SizedBox(height: 8),
          _toggleItem(
            context,
            title: l10n.fasterUploads,
            value: () =>
                localSettings.cfUploadProxyEnabled ??
                flagService.cloudflareUploadWorker,
            onChanged: () async {
              final newValue =
                  !(localSettings.cfUploadProxyEnabled ??
                      flagService.cloudflareUploadWorker);
              await localSettings.setCFUploadProxyEnabled(newValue);
            },
          ),
        ],
        if (Platform.isIOS) ...[
          const SizedBox(height: 24),
          _toggleItem(
            context,
            title: l10n.disableAutoLock,
            value: () => wakeLockService.shouldKeepAppAwakeAcrossSessions,
            onChanged: () async {
              wakeLockService.updateWakeLock(
                enable: !wakeLockService.shouldKeepAppAwakeAcrossSessions,
                wakeLockFor: WakeLockFor.fasterBackupsOniOSByKeepingScreenAwake,
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.only(
              left: Spacing.lg,
              right: Spacing.lg,
              top: Spacing.sm,
              bottom: Spacing.lg,
            ),
            child: Text(
              l10n.deviceLockExplanation,
              style: TextStyles.mini.copyWith(
                color: context.componentColors.textLight,
              ),
            ),
          ),
        ],
      ],
    );
  }

  MenuComponent _toggleItem(
    BuildContext context, {
    required String title,
    required bool Function() value,
    required Future<void> Function() onChanged,
  }) {
    return MenuComponent(
      title: title,
      trailing: ToggleSwitchComponent.async(value: value, onChanged: onChanged),
    );
  }
}

class _BackupOnlyNewPhotosToggle extends StatelessWidget {
  final Debouncer debouncer;

  const _BackupOnlyNewPhotosToggle({required this.debouncer});

  @override
  Widget build(BuildContext context) {
    return MenuComponent(
      title: context.l10n.backupOnlyNewPhotos,
      trailing: ToggleSwitchComponent.async(
        value: () => backupPreferenceService.isOnlyNewBackupEnabled,
        onChanged: () async {
          final hasPermission = await _ensurePhotoPermissions(context);
          if (!hasPermission) {
            return;
          }
          if (!context.mounted) return;
          final shouldProceed = await _maybeHandleFolderSelection(
            context: context,
          );
          if (!shouldProceed) {
            return;
          }
          final isEnabled = backupPreferenceService.isOnlyNewBackupEnabled;
          if (!isEnabled) {
            await backupPreferenceService.setOnlyNewSinceNow();
          } else {
            await backupPreferenceService.clearOnlyNewSinceEpoch();
          }
          debouncer.run(() async {
            await SyncService.instance.sync();
          });
          if (backupPreferenceService.hasSkippedOnboardingPermission) {
            await backupPreferenceService.setOnboardingPermissionSkipped(false);
          }
        },
      ),
    );
  }

  Future<bool> _ensurePhotoPermissions(BuildContext context) async {
    final state = await permissionService.requestPhotoMangerPermissions();
    if (state == PermissionState.authorized ||
        state == PermissionState.limited) {
      await permissionService.onUpdatePermission(state);
      SyncService.instance.onPermissionGranted().ignore();
      return true;
    }
    if (!context.mounted) {
      return false;
    }
    await showChoiceDialog(
      context,
      title: context.l10n.allowPermTitle,
      body: context.l10n.allowPermBody,
      firstButtonLabel: context.l10n.openSettings,
      secondButtonLabel: context.l10n.cancel,
      firstButtonOnTap: () async {
        await PhotoManager.openSetting();
      },
    );
    return false;
  }

  Future<bool> _maybeHandleFolderSelection({
    required BuildContext context,
  }) async {
    final needsFolderPrompt =
        !backupPreferenceService.hasManualFolderSelection &&
        (backupPreferenceService.hasSelectedAllFoldersForBackup ||
            !backupPreferenceService.hasSelectedAnyBackupFolder);
    if (!needsFolderPrompt) {
      return true;
    }

    final hasAllFoldersSelected =
        backupPreferenceService.hasSelectedAllFoldersForBackup;

    // Hide "Continue anyway" if user skipped permission and first import not done
    final allowContinueAnyway =
        !backupPreferenceService.hasSkippedOnboardingPermission ||
        LocalSyncService.instance.hasCompletedFirstImport();

    final result = await _showOnlyNewBackupFolderPrompt(
      context: context,
      hasAllFoldersSelected: hasAllFoldersSelected,
      allowContinueAnyway: allowContinueAnyway,
    );

    if (result == null) {
      return false;
    }

    if (result == _FolderPromptAction.selectFolders) {
      if (!context.mounted) return false;
      final bool? selected = await handleFolderSelectionBackupFlow(
        context,
        fromOnlyNewPhotosToggle: true,
      );
      if (selected != true) {
        return false;
      }
    } else if (result == _FolderPromptAction.continueAnyway) {
      await backupPreferenceService.setHasManualFolderSelection(true);
    }

    return true;
  }
}

Future<_FolderPromptAction?> _showOnlyNewBackupFolderPrompt({
  required BuildContext context,
  required bool hasAllFoldersSelected,
  required bool allowContinueAnyway,
}) async {
  final l10n = context.l10n;
  final message = hasAllFoldersSelected
      ? l10n.backupOnlyNewPhotosAllFoldersSelected
      : allowContinueAnyway
      ? l10n.backupOnlyNewPhotosNoFoldersSelectedContinue
      : l10n.backupOnlyNewPhotosNoFoldersSelectedRequire;
  return showBottomSheetComponent<_FolderPromptAction>(
    context: context,
    useRootNavigator: Platform.isIOS,
    builder: (sheetContext) => BottomSheetComponent(
      title: l10n.backupOnlyNewPhotos,
      closeTooltip: l10n.close,
      content: Text(
        message,
        style: TextStyles.body.copyWith(
          color: sheetContext.componentColors.textLight,
        ),
      ),
      actions: [
        ButtonComponent(
          label: l10n.selectFolders,
          shouldSurfaceExecutionStates: false,
          onTap: () async {
            Navigator.of(sheetContext).pop(_FolderPromptAction.selectFolders);
          },
        ),
        if (allowContinueAnyway)
          ButtonComponent(
            label: l10n.continueLabel,
            variant: ButtonComponentVariant.neutral,
            shouldSurfaceExecutionStates: false,
            onTap: () async {
              Navigator.of(
                sheetContext,
              ).pop(_FolderPromptAction.continueAnyway);
            },
          ),
      ],
    ),
  );
}

enum _FolderPromptAction { selectFolders, continueAnyway }
