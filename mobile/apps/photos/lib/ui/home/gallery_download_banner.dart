import "dart:async";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/gallery_downloads_events.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/module/download/manager.dart";
import "package:photos/module/download/task.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/app_lifecycle_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/buttons/button_widget.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/utils/dialog_util.dart";

class GalleryDownloadBanner extends StatefulWidget {
  const GalleryDownloadBanner({super.key});

  @override
  State<GalleryDownloadBanner> createState() => _GalleryDownloadBannerState();
}

class _GalleryDownloadBannerState extends State<GalleryDownloadBanner>
    with WidgetsBindingObserver {
  static const Duration _appReopenThreshold = Duration(seconds: 20);
  StreamSubscription<GalleryDownloadsUpdatedEvent>? _updatedSubscription;
  StreamSubscription<GalleryDownloadsResumedEvent>? _resumedSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    galleryDownloadQueueService.init().ignore();
    _updatedSubscription = Bus.instance
        .on<GalleryDownloadsUpdatedEvent>()
        .listen((_) {
          if (mounted) {
            setState(() {});
          }
        });
    _resumedSubscription = Bus.instance
        .on<GalleryDownloadsResumedEvent>()
        .listen((_) {
          if (mounted) {
            showToast(context, "Connection restored - resuming downloads");
          }
        });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updatedSubscription?.cancel();
    _resumedSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    final lastBackgroundTime = AppLifecycleService.instance
        .getLastAppOpenTime();
    if (lastBackgroundTime <= 0) {
      return;
    }
    final elapsed = DateTime.now().microsecondsSinceEpoch - lastBackgroundTime;
    if (elapsed >= _appReopenThreshold.inMicroseconds) {
      galleryDownloadQueueService.showBannerAfterAppReopen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = galleryDownloadQueueService;
    if (!service.isBannerVisible || service.orderedTasks.isEmpty) {
      return const SizedBox.shrink();
    }

    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final isErrorState =
        service.hasPausedDueToNoConnection ||
        service.hasPausedDueToStorage ||
        service.hasNonUnavailableErrors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: colorScheme.backgroundElevated2,
        borderRadius: const BorderRadius.all(Radius.circular(12)),
        child: InkWell(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          onTap: _openDetailsSheet,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.cloud_download_outlined,
                  color: isErrorState
                      ? colorScheme.warning500
                      : colorScheme.primary500,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_bannerMessage(context), style: textTheme.smallBold),
                      if (!service.isCompletionBannerVisible) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(2),
                          ),
                          child: LinearProgressIndicator(
                            value: service.overallProgress,
                            minHeight: 4,
                            color: isErrorState
                                ? colorScheme.warning500
                                : colorScheme.primary500,
                            backgroundColor: colorScheme.fillMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (service.isCompletionBannerVisible)
                  TextButton(
                    onPressed: () {
                      service.dismissCompletionBanner().ignore();
                    },
                    child: Text(AppLocalizations.of(context).dismiss),
                  )
                else
                  IconButton(
                    onPressed: service.dismissBanner,
                    icon: const Icon(Icons.close),
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    color: colorScheme.strokeBase,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _bannerMessage(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final service = galleryDownloadQueueService;

    if (service.isCompletionBannerVisible) {
      if (service.unavailableCount > 0) {
        return "${service.completedCount} of ${service.totalCount} saved - "
            "${service.unavailableCount} unavailable";
      }
      if (service.completedCount == 1) {
        return l10n.fileSavedToGallery;
      }
      return "${service.completedCount} files saved to gallery";
    }

    if (service.hasPausedDueToStorage) {
      return "Download paused - Not enough storage";
    }
    if (service.hasPausedDueToNoConnection) {
      return "Download paused - No connection";
    }
    if (service.hasNonUnavailableErrors) {
      return l10n.downloadFailed;
    }

    final current =
        (service.completedCount + (service.downloadingCount > 0 ? 1 : 0)).clamp(
          0,
          service.totalCount,
        );
    return "Downloading $current of ${service.totalCount}";
  }

  Future<void> _openDetailsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: false,
      backgroundColor: getEnteColorScheme(context).backgroundElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _DownloadsDetailSheet(),
    );
  }
}

class _DownloadsDetailSheet extends StatefulWidget {
  const _DownloadsDetailSheet();

  @override
  State<_DownloadsDetailSheet> createState() => _DownloadsDetailSheetState();
}

class _DownloadsDetailSheetState extends State<_DownloadsDetailSheet> {
  StreamSubscription<GalleryDownloadsUpdatedEvent>? _updatedSubscription;

  @override
  void initState() {
    super.initState();
    _updatedSubscription = Bus.instance
        .on<GalleryDownloadsUpdatedEvent>()
        .listen((_) {
          if (mounted) {
            setState(() {});
          }
        });
  }

  @override
  void dispose() {
    _updatedSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = galleryDownloadQueueService;
    final tasks = service.orderedTasks;
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final hasCancelableTasks = tasks.any(
      (task) =>
          task.status == DownloadStatus.pending ||
          task.status == DownloadStatus.downloading ||
          task.status == DownloadStatus.paused,
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.strokeMuted,
                borderRadius: const BorderRadius.all(Radius.circular(2)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text("Downloads", style: textTheme.h3Bold),
                const Spacer(),
                if (hasCancelableTasks)
                  TextButton(
                    onPressed: _confirmCancelAll,
                    child: const Text("Cancel all"),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text("No downloads", style: textTheme.smallMuted),
              )
            else
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: tasks.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: colorScheme.strokeFaint),
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return _DownloadTaskRow(task: task);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmCancelAll() async {
    final result = await showChoiceActionSheet(
      context,
      title: "Cancel all downloads?",
      body: "Queued and in-progress downloads will be cancelled.",
      firstButtonLabel: "Cancel all",
      isCritical: true,
    );
    if (!mounted) {
      return;
    }
    if (result?.action == ButtonAction.first) {
      await galleryDownloadQueueService.cancelAll();
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}

class _DownloadTaskRow extends StatelessWidget {
  const _DownloadTaskRow({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final canCancel =
        task.status == DownloadStatus.pending ||
        task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.paused;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.body,
                ),
                const SizedBox(height: 4),
                _TaskStatus(task: task),
              ],
            ),
          ),
          if (canCancel)
            IconButton(
              onPressed: () =>
                  galleryDownloadQueueService.cancelTask(task.id).ignore(),
              icon: const Icon(Icons.close),
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              color: colorScheme.strokeMuted,
            ),
        ],
      ),
    );
  }
}

class _TaskStatus extends StatelessWidget {
  const _TaskStatus({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    switch (task.status) {
      case DownloadStatus.completed:
        return Row(
          children: [
            Icon(Icons.check_circle, size: 14, color: colorScheme.primary500),
            const SizedBox(width: 6),
            Text(
              "Saved",
              style: textTheme.mini.copyWith(color: colorScheme.primary500),
            ),
          ],
        );
      case DownloadStatus.downloading:
        final progress = task.progress.clamp(0.0, 1.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(2)),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: colorScheme.fillMuted,
                color: colorScheme.primary500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "${(progress * 100).toStringAsFixed(0)}%",
              style: textTheme.miniMuted,
            ),
          ],
        );
      case DownloadStatus.pending:
        return Text(
          "${AppLocalizations.of(context).queued} • ${formatBytes(task.totalBytes)}",
          style: textTheme.miniMuted,
        );
      case DownloadStatus.paused:
      case DownloadStatus.error:
      case DownloadStatus.cancelled:
        return Text(
          _errorMessage(context, task.error),
          style: textTheme.mini.copyWith(color: colorScheme.warning500),
        );
    }
  }

  String _errorMessage(BuildContext context, String? error) {
    if (error == DownloadManager.noConnectionError) {
      return "No connection";
    }
    if (error == DownloadManager.notEnoughStorageError) {
      return "Not enough storage";
    }
    if (error == DownloadManager.unavailableError) {
      return "Unavailable";
    }
    if (error == DownloadManager.applePhotosUnsupportedResourceError) {
      return AppLocalizations.of(context).applePhotosUnsupportedResource;
    }
    if (error == null || error.isEmpty) {
      return "Download failed";
    }
    return error;
  }
}
