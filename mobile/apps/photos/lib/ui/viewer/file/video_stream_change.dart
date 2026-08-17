import "dart:async";

import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/video_preview_state_changed_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/preview/preview_item_status.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/video_preview_service.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart" show getEnteTextTheme;

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
    isCurrentlyProcessing = VideoPreviewService.instance.isCurrentlyProcessing(
      widget.file.uploadedFileID,
    );

    _subscription = Bus.instance.on<VideoPreviewStateChangedEvent>().listen((
      event,
    ) {
      final fileId = event.fileId;
      final status = event.status;

      final newProcessingState =
          widget.file.uploadedFileID == fileId &&
          switch (status) {
            PreviewItemStatus.inQueue ||
            PreviewItemStatus.retry ||
            PreviewItemStatus.compressing ||
            PreviewItemStatus.uploading => true,
            _ => false,
          };

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
        return context.strings.queued;
      case PreviewItemStatus.compressing:
      case PreviewItemStatus.uploading:
      default:
        return context.strings.creatingStream;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isPreviewAvailable =
        widget.file.uploadedFileID != null &&
        (fileDataService.previewIds.containsKey(widget.file.uploadedFileID));

    final processingStatus = widget.file.uploadedFileID != null
        ? VideoPreviewService.instance.getProcessingStatus(
            widget.file.uploadedFileID!,
          )
        : null;

    if (!isPreviewAvailable && !isCurrentlyProcessing) {
      return const SizedBox();
    }

    return IgnorePointer(
      ignoring: !widget._showControls,
      child: Align(
        alignment: Alignment.centerRight,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInQuad,
          opacity: widget._showControls ? 1 : 0,
          child: Padding(
            padding: const EdgeInsets.only(right: 10, bottom: 4),
            child: GestureDetector(
              onTap: isCurrentlyProcessing ? null : widget.onStreamChange,
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.all(Radius.circular(16)),
                  border: Border.all(color: strokeFaintDark),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isCurrentlyProcessing)
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: textBaseDark,
                        ),
                      )
                    else
                      const HugeIcon(
                        icon: HugeIcons.strokeRoundedPlay,
                        size: 16,
                        color: textBaseDark,
                      ),
                    SizedBox(width: isCurrentlyProcessing ? 8 : 4),
                    Text(
                      isCurrentlyProcessing
                          ? _getStatusText(context, processingStatus)
                          : widget.isPreviewPlayer
                          ? context.strings.playOriginal
                          : context.strings.playStream,
                      style: getEnteTextTheme(
                        context,
                      ).mini.copyWith(color: textBaseDark),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
