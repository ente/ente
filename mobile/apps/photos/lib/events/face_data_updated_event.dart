import "package:photos/events/event.dart";

class FaceDataUpdatedEvent extends Event {
  final Set<int> fileIDs;
  final bool localGallery;

  FaceDataUpdatedEvent(this.fileIDs, {required this.localGallery});
}
