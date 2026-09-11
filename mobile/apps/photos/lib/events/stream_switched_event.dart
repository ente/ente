import "package:photos/events/event.dart";

class StreamSwitchedEvent extends Event {
  final bool selectedPreview;
  final PlayerType type;
  final String fileTag;

  StreamSwitchedEvent(this.selectedPreview, this.type, {required this.fileTag});
}

enum PlayerType { mediaKit, nativeVideoPlayer }
