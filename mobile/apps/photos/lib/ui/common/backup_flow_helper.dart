import "dart:async";
import "dart:io";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/sync/local_sync_service.dart";
import "package:photos/ui/home/loading_photos_widget.dart";
import "package:photos/ui/settings/backup/backup_folder_selection_page.dart";
import "package:photos/utils/dialog_util.dart";

final _logger = Logger("BackupFlowHelper");

Future<void> handleFullPermissionBackupFlow(BuildContext context) async {
  if (_shouldRunFirstImportFlow()) {
    await _handleFirstImportFlow(context);
    return;
  }

  final state = await _requestAndStoreGrantedPermissions();
  if (!context.mounted) return;

  final hasFullPermission =
      state == PermissionState.authorized ||
      (state == null && permissionService.hasGrantedFullPermission());
  if (hasFullPermission) {
    unawaited(_navigateToFolderSelection(context, isFirstBackup: false));
  } else if (Platform.isAndroid) {
    await PhotoManager.openSetting();
  } else {
    final hasLimitedPermission =
        state == PermissionState.limited ||
        (state == null && permissionService.hasGrantedLimitedPermissions());
    // ignore: unawaited_futures
    _showLimitedPermissionSheet(context, hasGrantedLimit: hasLimitedPermission);
  }
}

Future<void> handleLimitedOrFolderBackupFlow(
  BuildContext context, {
  bool isFirstBackup = true,
}) async {
  if (_shouldRunFirstImportFlow()) {
    await _handleFirstImportFlow(context);
    return;
  }

  if (permissionService.hasGrantedLimitedPermissions()) {
    unawaited(PhotoManager.presentLimited());
  } else {
    unawaited(
      _navigateToFolderSelection(context, isFirstBackup: isFirstBackup),
    );
  }
}

Future<bool?> handleFolderSelectionBackupFlow(
  BuildContext context, {
  bool isFirstBackup = false,
  bool fromOnlyNewPhotosToggle = false,
}) async {
  if (_shouldRunFirstImportFlow()) {
    return _handleFirstImportFlow(context);
  }

  return _navigateToFolderSelection(
    context,
    isFirstBackup: isFirstBackup,
    fromOnlyNewPhotosToggle: fromOnlyNewPhotosToggle,
  );
}

bool _shouldRunFirstImportFlow() =>
    !LocalSyncService.instance.hasCompletedFirstImport();

Future<bool?> _handleFirstImportFlow(BuildContext context) async {
  final state = await _requestAndStoreGrantedPermissions();
  if (state == null || !context.mounted) return null;

  if (!_hasMinimalPermission(state)) {
    await _showPermissionDeniedDialog(context);
    return null;
  }

  // Trigger local sync before showing the loading widget.
  // The skip flag was cleared above, so sync will now proceed with first import.
  // We use LocalSyncService.sync() directly because:
  // 1. It has its own _existingSync guard - returns existing future if already running
  // 2. It's all we need for first import (fires completedFirstGalleryImport event)
  // 3. Avoids race conditions with SyncService._doSync() calling syncAll()
  _logger.info("Triggering local sync for first import from backup flow");
  unawaited(LocalSyncService.instance.sync());

  return routeToPage<bool>(
    context,
    const LoadingPhotosWidget(isOnboardingFlow: false),
  );
}

Future<PermissionState?> _requestAndStoreGrantedPermissions() async {
  try {
    final state = await permissionService.requestPhotoMangerPermissions();
    if (_hasMinimalPermission(state)) {
      await permissionService.onUpdatePermission(state);
    }
    return state;
  } catch (e, s) {
    _logger.severe("Failed to request permission", e, s);
    return null;
  }
}

bool _hasMinimalPermission(PermissionState state) =>
    state == PermissionState.authorized || state == PermissionState.limited;

Future<bool?> _navigateToFolderSelection(
  BuildContext context, {
  required bool isFirstBackup,
  bool fromOnlyNewPhotosToggle = false,
}) => routeToPage<bool>(
  context,
  BackupFolderSelectionPage(
    isFirstBackup: isFirstBackup,
    fromOnlyNewPhotosToggle: fromOnlyNewPhotosToggle,
  ),
);

Future<void> _showPermissionDeniedDialog(BuildContext context) =>
    showChoiceDialog(
      context,
      title: context.l10n.allowPermTitle,
      body: context.l10n.allowPermBody,
      firstButtonLabel: context.l10n.openSettings,
      firstButtonOnTap: () async => PhotoManager.openSetting(),
    );

Future<void> _showLimitedPermissionSheet(
  BuildContext context, {
  required bool hasGrantedLimit,
}) => showChoiceActionSheet(
  context,
  title: context.l10n.preserveMore,
  body: context.l10n.grantFullAccessPrompt,
  firstButtonLabel: context.l10n.openSettings,
  firstButtonOnTap: () async => PhotoManager.openSetting(),
  secondButtonLabel: hasGrantedLimit
      ? context.l10n.selectMorePhotos
      : context.l10n.cancel,
  secondButtonOnTap: () async {
    if (hasGrantedLimit) await PhotoManager.presentLimited();
  },
);
