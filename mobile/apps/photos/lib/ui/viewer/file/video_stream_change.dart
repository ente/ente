import "package:ente_strings/ente_strings.dart";
import "package:flutter/widgets.dart";
import "package:photos/models/preview/preview_item_status.dart";

@immutable
class VideoStreamChangeState {
  final bool isPreviewPlayer;
  final bool isCurrentlyProcessing;
  final PreviewItemStatus? processingStatus;
  final VoidCallback onStreamChange;

  const VideoStreamChangeState({
    required this.isPreviewPlayer,
    required this.isCurrentlyProcessing,
    required this.processingStatus,
    required this.onStreamChange,
  });

  bool get canChangeStream => !isCurrentlyProcessing;

  String label(BuildContext context) {
    if (isCurrentlyProcessing) {
      return switch (processingStatus) {
        PreviewItemStatus.inQueue ||
        PreviewItemStatus.retry => context.strings.queued,
        _ => context.strings.creatingStream,
      };
    }
    return isPreviewPlayer
        ? context.strings.playOriginal
        : context.strings.playStream;
  }
}

// Publishes the stream action owned by the video player to viewer chrome.
//
// The owner token prevents a retiring player from clearing a newer player's
// action when Flutter replaces a page during navigation or file removal.
class VideoStreamChangeController
    extends ValueNotifier<VideoStreamChangeState?> {
  VideoStreamChangeController() : super(null);

  Object? _owner;

  void update(Object owner, VideoStreamChangeState state) {
    _owner = owner;
    value = state;
  }

  void clear(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    value = null;
  }
}
