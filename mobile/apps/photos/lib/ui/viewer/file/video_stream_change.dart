import "dart:async";

import "package:flutter/material.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/video_preview_state_changed_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/preview/preview_item_status.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/video_preview_service.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart" show getEnteColorScheme;

class VideoStreamChangeWidget extends StatefulWidget {
  const VideoStreamChangeWidget({
    super.key,
    required bool showControls,
    required this.file,
    required this.onStreamChange,
    this.isPreviewPlayer = false,
  }) : _showControls = showControls;

  final bool _showControls;
  final EnteFile file;
  final bool isPreviewPlayer;
  final void Function()? onStreamChange;

  @override
  State<VideoStreamChangeWidget> createState() =>
      _VideoStreamChangeWidgetState();
}

class _VideoStreamChangeWidgetState extends State<VideoStreamChangeWidget> {
  StreamSubscription<VideoPreviewStateChangedEvent>? _subscription;
  bool isCurrentlyProcessing = false;

  @override
  void initState() {
    super.initState();
    // Initialize processing state safely in initState
    isCurrentlyProcessing = VideoPreviewService.instance.isCurrentlyProcessing(
      widget.file.uploadedFileID,
    );

    _subscription = Bus.instance.on<VideoPreviewStateChangedEvent>().listen((
      event,
    ) {
      final fileId = event.fileId;
      final status = event.status;

      // Handle different states - will be false for different files or non-processing states
      final newProcessingState =
          widget.file.uploadedFileID == fileId &&
          switch (status) {
            PreviewItemStatus.inQueue ||
            PreviewItemStatus.retry ||
            PreviewItemStatus.compressing ||
            PreviewItemStatus.uploading => true,
            _ => false,
          };

      // Only update state if value changed
      if (isCurrentlyProcessing != newProcessingState) {
        isCurrentlyProcessing = newProcessingState;
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  String _getStatusText(BuildContext context, PreviewItemStatus? status) {
    switch (status) {
      case PreviewItemStatus.inQueue:
      case PreviewItemStatus.retry:
        return AppLocalizations.of(context).queued;
      case PreviewItemStatus.compressing:
      case PreviewItemStatus.uploading:
      default:
        return AppLocalizations.of(context).creatingStream;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isPreviewAvailable =
        widget.file.uploadedFileID != null &&
        (fileDataService.previewIds.containsKey(widget.file.uploadedFileID));

    // Get the current processing status for more specific messaging
    final processingStatus = widget.file.uploadedFileID != null
        ? VideoPreviewService.instance.getProcessingStatus(
            widget.file.uploadedFileID!,
          )
        : null;

    final colorScheme = getEnteColorScheme(context);

    if (!isPreviewAvailable && !isCurrentlyProcessing) {
      return const SizedBox();
    }

    // If currently processing, show "Creating Stream" with spinner (not clickable)

    return Align(
      alignment: Alignment.centerRight,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInQuad,
        opacity: widget._showControls ? 1 : 0,
        child: Padding(
          padding: const EdgeInsets.only(right: 10, bottom: 4),
          child: isCurrentlyProcessing
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.backdropBase,
                    borderRadius: const BorderRadius.all(Radius.circular(200)),
                    border: Border.all(color: strokeFaintDark, width: 1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            colorScheme.fillBase,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _getStatusText(context, processingStatus),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.fillBase,
                        ),
                      ),
                    ],
                  ),
                )
              : GestureDetector(
                  onTap: widget.onStreamChange,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(200),
                      ),
                      border: Border.all(color: strokeFaintDark, width: 1),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.play_arrow,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          widget.isPreviewPlayer
                              ? AppLocalizations.of(context).playOriginal
                              : AppLocalizations.of(context).playStream,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
