import "dart:async";

import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/loading_widget.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter_animate/flutter_animate.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/collection_updated_event.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/sync_finished_event.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/models/ignored_file.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/ignored_files_service.dart";
import "package:photos/services/sync/remote_sync_service.dart";
import "package:photos/services/sync/sync_service.dart";
import "package:photos/ui/notification/toast.dart";

class UploadIconWidget extends StatefulWidget {
  final EnteFile file;

  const UploadIconWidget({super.key, required this.file});

  @override
  State<StatefulWidget> createState() {
    return _UpdateIconWidgetState();
  }
}

class _UpdateIconWidgetState extends State<UploadIconWidget> {
  final Logger _logger = Logger("_UpdateIconWidgetState");
  late StreamSubscription<CollectionUpdatedEvent> _firstImportEvent;
  late StreamSubscription<SyncFinishedEvent> _syncFinishedEvent;
  late IgnoredFilesService ignoreService;
  bool isUploadedNow = false;
  bool isBeingUploaded = false;
  bool _isHiddenForSync = false;
  bool _hasFinishedUploadAnimation = false;

  @override
  void initState() {
    super.initState();
    ignoreService = IgnoredFilesService.instance;
    _syncFinishedEvent = Bus.instance.on<SyncFinishedEvent>().listen((_) {
      if (mounted && _isHiddenForSync) {
        setState(() {});
      }
    });
    _firstImportEvent = Bus.instance.on<CollectionUpdatedEvent>().listen((
      event,
    ) {
      if (mounted &&
          event.type == EventType.addedOrUpdated &&
          event.updatedFiles.isNotEmpty &&
          event.updatedFiles.first.localID == widget.file.localID &&
          event.updatedFiles.first.isUploaded) {
        setState(() {
          isUploadedNow = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _firstImportEvent.cancel();
    _syncFinishedEvent.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _isHiddenForSync = SyncService.instance.isSyncInProgress();
    if (_isHiddenForSync) {
      if (!widget.file.isUploaded) {
        _logger.info("sync in progress ${widget.file.displayName}");
      }
      return const SizedBox.shrink();
    }
    if (widget.file.isUploaded || isUploadedNow) {
      if (isUploadedNow && !_hasFinishedUploadAnimation) {
        return SizedBox.square(
          dimension: kMinInteractiveDimension,
          child: Center(
            child:
                const HugeIcon(
                      icon: HugeIcons.strokeRoundedCloudSavingDone01,
                      color: Colors.white,
                    )
                    .animate(
                      onComplete: (_) {
                        if (mounted) {
                          setState(() {
                            _hasFinishedUploadAnimation = true;
                          });
                        }
                      },
                    )
                    .fadeIn(duration: 500.ms, curve: Curves.easeInOutCubic)
                    .fadeOut(
                      delay: const Duration(seconds: 3),
                      duration: 500.ms,
                      curve: Curves.easeInOutCubic,
                    ),
          ),
        );
      }
      return const SizedBox.shrink();
    }
    return FutureBuilder<Map<String, String>>(
      future: ignoreService.idToIgnoreReasonMap,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          final Map<String, String> idsToReasonMap = snapshot.data!;
          final ignoreReason = ignoreService.getUploadSkipReason(
            idsToReasonMap,
            widget.file,
          );
          final bool isIgnored = ignoreReason != null;
          final bool isQueuedForUpload =
              !isIgnored && widget.file.collectionID != null;
          if (isQueuedForUpload && isBeingUploaded) {
            return const SizedBox.square(
              dimension: kMinInteractiveDimension,
              child: EnteLoadingWidget(color: Colors.white, size: 16),
            );
          }
          if (isIgnored && (kDebugMode || ignoreReason != kIgnoreReasonTrash)) {
            showToast(
              context,
              context.strings.uploadIsIgnoredDueToIgnorereason(
                ignoreReason: ignoreReason,
              ),
            );
          }
          return Tooltip(
            message: isIgnored
                ? context.strings.tapToUploadIsIgnoredDue(
                    ignoreReason: ignoreReason,
                  )
                : context.strings.tapToUpload,
            child: IconButton(
              icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedUpload01,
                color: Colors.white,
              ),
              onPressed: () async {
                if (isIgnored) {
                  await IgnoredFilesService.instance.removeIgnoredMappings([
                    widget.file,
                  ]);
                }
                if (widget.file.collectionID == null) {
                  widget.file.collectionID =
                      (await CollectionsService.instance
                              .getUncategorizedCollection())
                          .id;
                  await FilesDB.instance.insert(widget.file);
                }
                await RemoteSyncService.instance.whiteListVideoForUpload(
                  widget.file,
                );
                RemoteSyncService.instance.sync().ignore();
                if (mounted) {
                  setState(() {
                    isBeingUploaded = true;
                  });
                }
              },
            ),
          );
        } else {
          return const SizedBox.shrink();
        }
      },
    );
  }
}
