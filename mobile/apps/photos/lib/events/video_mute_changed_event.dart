import "package:photos/events/event.dart";

class VideoMuteChangedEvent extends Event {
  final bool isMuted;

  VideoMuteChangedEvent(this.isMuted);
}
