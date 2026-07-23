import 'dart:math';

import 'package:ente_components/ente_components.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:photos/db/device_files_db.dart';
import 'package:photos/db/files_db.dart';
import 'package:photos/generated/l10n.dart';
import 'package:photos/models/device_collection.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/sync/remote_sync_service.dart';
import 'package:photos/ui/common/loading_widget.dart';
import 'package:photos/ui/components/collection_share_badge.dart';
import 'package:photos/ui/settings/backup/backup_settings_screen.dart';
import 'package:photos/ui/viewer/file/thumbnail_widget.dart';
import 'package:photos/utils/dialog_util.dart';

class BackupFolderSelectionPage extends StatefulWidget {
  final bool isFirstBackup;
  final bool isOnboarding;

  /// When true, skip the "only new backup" warning dialog.
  /// This is used when coming from the "backup only new photos" toggle
  /// to prevent recursive navigation back to backup settings.
  final bool fromOnlyNewPhotosToggle;

  const BackupFolderSelectionPage({
    required this.isFirstBackup,
    this.isOnboarding = false,
    this.fromOnlyNewPhotosToggle = false,
    super.key,
  });

  @override
  State<BackupFolderSelectionPage> createState() =>
      _BackupFolderSelectionPageState();
}

class _BackupFolderSelectionPageState extends State<BackupFolderSelectionPage> {
  final Logger _logger = Logger((_BackupFolderSelectionPageState).toString());
  final Set<String> _allDevicePathIDs = <String>{};
  final Set<String> _selectedDevicePathIDs = <String>{};
  List<DeviceCollection>? _deviceCollections;
  Map<String, int>? _pathIDToItemCount;
  late final bool _treatAsOnboarding;

  static const _maxThumbnailWidth = 224.0;
  static const _gridHorizontalPadding = 16.0;
  static const _gridCrossSpacing = 8.0;
  static const _gridMainSpacing = 8.0;
  static const _cornerRadius = 20.0;
  static const _cornerSmoothing = 0.6;
  static const _thumbnailToTextSpacing = 8.0;
  static const _titleToSubtitleSpacing = 4.0;

  @override
  void initState() {
    _treatAsOnboarding =
        widget.isOnboarding ||
        backupPreferenceService.hasSkippedOnboardingPermission;
    FilesDB.instance.getDeviceCollections(includeCoverThumbnail: true).then((
      files,
    ) async {
      _pathIDToItemCount = await FilesDB.instance
          .getDevicePathIDToImportedFileCount();
      if (!mounted) {
        return;
      }
      setState(() {
        _deviceCollections = files;
        _deviceCollections!.sort((first, second) {
          return first.name.toLowerCase().compareTo(second.name.toLowerCase());
        });
        for (final file in _deviceCollections!) {
          _allDevicePathIDs.add(file.id);
          if (file.shouldBackup) {
            _selectedDevicePathIDs.add(file.id);
          }
        }
        if (_treatAsOnboarding) {
          _selectedDevicePathIDs.addAll(_allDevicePathIDs);
        }
        _selectedDevicePathIDs.removeWhere(
          (folder) => !_allDevicePathIDs.contains(folder),
        );
      });
    });
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Scaffold(
      backgroundColor: colors.backgroundBase,
      body: _buildScrollableBody(),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Future<void> updateFolderSettings() async {
    final l10n = AppLocalizations.of(context);
    final dialog = createProgressDialog(context, l10n.updatingFolderSelection);
    await dialog.show();
    try {
      final Map<String, bool> syncStatus = {};
      for (String pathID in _allDevicePathIDs) {
        syncStatus[pathID] = _selectedDevicePathIDs.contains(pathID);
      }
      await backupPreferenceService.setHasSelectedAnyBackupFolder(
        _selectedDevicePathIDs.isNotEmpty,
      );
      await backupPreferenceService.setSelectAllFoldersForBackup(
        _allDevicePathIDs.length == _selectedDevicePathIDs.length,
      );
      await RemoteSyncService.instance.updateDeviceFolderSyncStatus(syncStatus);
      await dialog.hide();
      await backupPreferenceService.setHasManualFolderSelection(true);

      // Skip the warning dialog if we came from the "backup only new photos"
      // toggle to avoid recursive navigation back to backup settings.
      final onlyNewSinceEpoch = backupPreferenceService.onlyNewSinceEpoch;
      if (onlyNewSinceEpoch != null && !widget.fromOnlyNewPhotosToggle) {
        final shouldContinue = await _showOnlyNewBackupWarning(
          onlyNewSinceEpoch,
        );

        if (!shouldContinue) return;
      }

      if (context.mounted) {
        if (!mounted) return;
        Navigator.of(context).pop(true);
      }
    } catch (e, s) {
      _logger.severe("Failed to updated backup folder", e, s);
      await dialog.hide();
      if (!mounted) return;
      await showGenericErrorDialog(context: context, error: e);
    }
  }

  Future<bool> _showOnlyNewBackupWarning(int onlyNewSinceEpoch) async {
    final l10n = AppLocalizations.of(context);
    final date = DateTime.fromMicrosecondsSinceEpoch(onlyNewSinceEpoch);
    final locale = Localizations.localeOf(context).languageCode;
    final formattedDate = DateFormat.yMMMd(locale).format(date);

    final result = await showBottomSheetComponent<_OnlyNewWarningAction>(
      context: context,
      builder: (sheetContext) => BottomSheetComponent(
        title: l10n.warning,
        message: l10n.backupOnlyNewPhotosWarningBody(
          formattedDate: formattedDate,
        ),
        illustration: Image.asset("assets/warning-grey.png"),
        actions: [
          ButtonComponent(
            label: l10n.updateSettings,
            variant: ButtonComponentVariant.neutral,
            shouldSurfaceExecutionStates: false,
            onTap: () async {
              Navigator.of(
                sheetContext,
              ).pop(_OnlyNewWarningAction.updateSettings);
            },
          ),
          ButtonComponent(
            label: l10n.ok,
            shouldSurfaceExecutionStates: false,
            onTap: () async {
              Navigator.of(
                sheetContext,
              ).pop(_OnlyNewWarningAction.continueBackup);
            },
          ),
        ],
      ),
    );

    if (!context.mounted) {
      return false;
    }
    if (result == _OnlyNewWarningAction.updateSettings) {
      if (!mounted) return false;
      await routeToPage(context, const BackupSettingsScreen());
      return false;
    }
    if (result == _OnlyNewWarningAction.continueBackup) {
      return true;
    }

    return false;
  }

  Widget _buildBottomNavigationBar() {
    final l10n = AppLocalizations.of(context);
    final colors = context.componentColors;
    final canSubmit = !(_treatAsOnboarding && _selectedDevicePathIDs.isEmpty);

    return Container(
      color: colors.backgroundBase,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ButtonComponent(
                label: widget.isFirstBackup ? l10n.startBackup : l10n.backup,
                isDisabled: !canSubmit,
                onTap: canSubmit
                    ? () async {
                        await updateFolderSettings();
                      }
                    : null,
              ),
              if (_treatAsOnboarding) ...[
                const SizedBox(height: 16),
                ButtonComponent(
                  key: const ValueKey("skipBackupButton"),
                  label: l10n.skip,
                  variant: ButtonComponentVariant.link,
                  onTap: () async {
                    Navigator.of(context).pop(false);
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScrollableBody() {
    final l10n = AppLocalizations.of(context);
    final colors = context.componentColors;

    return AppBarComponent(
      title: l10n.backupToEnte,
      subtitle: l10n.selectAlbumsToBackUpToEnte,
      showExpandedBackButton: !_treatAsOnboarding,
      slivers: [
        if (_deviceCollections != null)
          SliverToBoxAdapter(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggleSelectAll,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      _selectedDevicePathIDs.length == _allDevicePathIDs.length
                          ? l10n.unselectAll
                          : l10n.selectAll,
                      style: TextStyles.body.copyWith(
                        color: colors.textBase,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        _buildFoldersSliver(),
      ],
    );
  }

  Widget _buildFoldersSliver() {
    if (_deviceCollections == null) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: EnteLoadingWidget(),
      );
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final crossAxisCount = max(screenWidth ~/ _maxThumbnailWidth, 3);
    final totalCrossAxisSpacing = (crossAxisCount - 1) * _gridCrossSpacing;
    final sideOfThumbnail =
        (screenWidth - totalCrossAxisSpacing - _gridHorizontalPadding) /
        crossAxisCount;
    final gridItemTextHeight = _gridItemTextHeight(context);

    return SliverPadding(
      padding: const EdgeInsets.symmetric(
        horizontal: _gridHorizontalPadding / 2,
      ),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate((context, index) {
          return _buildFolderItem(_deviceCollections![index], sideOfThumbnail);
        }, childCount: _deviceCollections!.length),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: _gridCrossSpacing,
          mainAxisSpacing: _gridMainSpacing,
          childAspectRatio:
              sideOfThumbnail / (sideOfThumbnail + gridItemTextHeight),
        ),
      ),
    );
  }

  double _gridItemTextHeight(BuildContext context) {
    final textScaler = MediaQuery.textScalerOf(context);
    return (_thumbnailToTextSpacing +
            _scaledLineHeight(textScaler, TextStyles.body) +
            _titleToSubtitleSpacing +
            _scaledLineHeight(textScaler, TextStyles.mini))
        .ceilToDouble();
  }

  double _scaledLineHeight(TextScaler textScaler, TextStyle style) {
    final fontSize = style.fontSize ?? 14;
    return textScaler.scale(fontSize) * (style.height ?? 1);
  }

  Widget _buildFolderItem(
    DeviceCollection deviceCollection,
    double sideOfThumbnail,
  ) {
    final colors = context.componentColors;
    final l10n = AppLocalizations.of(context);
    final isSelected = _selectedDevicePathIDs.contains(deviceCollection.id);
    final importedCount = _pathIDToItemCount?[deviceCollection.id];
    final formattedCount = NumberFormat().format(deviceCollection.count);
    final countText = kDebugMode && importedCount != null
        ? "inApp: $importedCount | device: $formattedCount"
        : l10n.itemCount(count: deviceCollection.count);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleFolderSelection(deviceCollection.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: sideOfThumbnail,
            height: sideOfThumbnail,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                ClipSmoothRect(
                  radius: SmoothBorderRadius(
                    cornerRadius: _cornerRadius,
                    cornerSmoothing: _cornerSmoothing,
                  ),
                  child: SizedBox(
                    width: sideOfThumbnail,
                    height: sideOfThumbnail,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (deviceCollection.thumbnail != null)
                          ThumbnailWidget(
                            deviceCollection.thumbnail!,
                            shouldShowSyncStatus: false,
                            key: ValueKey(
                              "backup_selection_widget_${deviceCollection.id}",
                            ),
                          )
                        else
                          ColoredBox(color: colors.fillDark),
                        if (isSelected)
                          ColoredBox(
                            color: Colors.black.withValues(alpha: 0.4),
                          ),
                        if (isSelected)
                          const Positioned(
                            top: 8,
                            right: 8,
                            child: CollectionSelectedBadge(),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: _thumbnailToTextSpacing),
          SizedBox(
            width: sideOfThumbnail,
            child: Text(
              deviceCollection.name,
              textAlign: TextAlign.left,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyles.body.copyWith(color: colors.textBase),
            ),
          ),
          const SizedBox(height: _titleToSubtitleSpacing),
          SizedBox(
            width: sideOfThumbnail,
            child: Text(
              countText,
              textAlign: TextAlign.left,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyles.mini.copyWith(color: colors.textLight),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleSelectAll() {
    setState(() {
      final hasSelectedAll =
          _selectedDevicePathIDs.length == _allDevicePathIDs.length;
      if (hasSelectedAll) {
        _selectedDevicePathIDs.clear();
      } else {
        _selectedDevicePathIDs.addAll(_allDevicePathIDs);
      }
    });
  }

  void _toggleFolderSelection(String folderId) {
    setState(() {
      if (_selectedDevicePathIDs.contains(folderId)) {
        _selectedDevicePathIDs.remove(folderId);
      } else {
        _selectedDevicePathIDs.add(folderId);
      }
    });
  }
}

enum _OnlyNewWarningAction { updateSettings, continueBackup }
