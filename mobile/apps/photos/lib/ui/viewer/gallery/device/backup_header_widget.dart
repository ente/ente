import "dart:async";

import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/device_collection.dart";
import "package:photos/models/ignored_upload_reason.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/menu_item_widget/menu_item_widget_new.dart";
import "package:photos/ui/components/toggle_switch_widget.dart";
import "package:photos/ui/viewer/gallery/device/ignored_uploads.dart";

class BackupHeaderWidget extends StatefulWidget {
  final DeviceCollection deviceCollection;
  final bool shouldBackup;
  final Future<bool> Function(bool shouldBackup) onBackupChanged;
  final Future<void> Function() onOpenSkippedFiles;

  const BackupHeaderWidget(
    this.deviceCollection, {
    required this.shouldBackup,
    required this.onBackupChanged,
    required this.onOpenSkippedFiles,
    super.key,
  });

  @override
  State<BackupHeaderWidget> createState() => _BackupHeaderWidgetState();
}

class _BackupHeaderWidgetState extends State<BackupHeaderWidget> {
  final _logger = Logger("_BackupHeaderWidgetState");
  late final StreamSubscription<LocalPhotosUpdatedEvent> _localPhotosSub;
  Future<Set<IgnoredUploadReasonBucket>> _ignoredUploadBuckets = Future.value(
    const <IgnoredUploadReasonBucket>{},
  );

  @override
  void initState() {
    super.initState();
    _localPhotosSub = Bus.instance.on<LocalPhotosUpdatedEvent>().listen((_) {
      if (!mounted || !widget.shouldBackup) {
        return;
      }
      setState(_refreshIgnoredState);
    });
    if (widget.shouldBackup) {
      _refreshIgnoredState();
    }
  }

  @override
  void didUpdateWidget(covariant BackupHeaderWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shouldBackup &&
        (oldWidget.deviceCollection.id != widget.deviceCollection.id ||
            !oldWidget.shouldBackup)) {
      _refreshIgnoredState();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.shouldBackup) {
      return _buildSkippedFilesRow(context);
    }
    return _paddedHeader(_buildBackupRow(context));
  }

  Widget _buildBackupRow(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return MenuItemWidgetNew(
      title: l10n.backup,
      subText: l10n.autoUploadFromThisDeviceFolder,
      titleToSubTextSpacing: 2,
      leadingIconWidget: _menuIcon(context, HugeIcons.strokeRoundedUpload01),
      trailingWidget: ToggleSwitchWidget(
        value: () => widget.shouldBackup,
        onChanged: () async {
          await widget.onBackupChanged(!widget.shouldBackup);
        },
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  Widget _buildSkippedFilesRow(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return FutureBuilder<Set<IgnoredUploadReasonBucket>>(
      future: _ignoredUploadBuckets,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          _logger.severe("Could not check if collection has ignored files");
          return const SizedBox.shrink();
        }
        final visibleBuckets = visibleIgnoredUploadBuckets(
          snapshot.data ?? <IgnoredUploadReasonBucket>{},
        );
        if (visibleBuckets.isEmpty) {
          return const SizedBox.shrink();
        }
        return _paddedHeader(
          MenuItemWidgetNew(
            title: l10n.skippedFiles,
            subText: l10n.chooseReasonToViewFiles,
            titleToSubTextSpacing: 2,
            leadingIconWidget: _menuIcon(
              context,
              HugeIcons.strokeRoundedReload,
            ),
            trailingIcon: Icons.chevron_right_outlined,
            trailingIconIsMuted: true,
            onTap: () async {
              await widget.onOpenSkippedFiles();
              if (!mounted) {
                return;
              }
              setState(_refreshIgnoredState);
            },
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        );
      },
    );
  }

  Widget _paddedHeader(Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: child,
    );
  }

  void _refreshIgnoredState() {
    _ignoredUploadBuckets = ignoredUploadReasonBuckets(
      filesInDeviceCollectionFor(widget.deviceCollection),
    );
  }

  @override
  void dispose() {
    _localPhotosSub.cancel();
    super.dispose();
  }
}

Widget _menuIcon(BuildContext context, List<List<dynamic>> icon) {
  return HugeIcon(
    icon: icon,
    color: getEnteColorScheme(context).menuItemIconStroke,
    size: 20,
  );
}
