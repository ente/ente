import "package:photos/events/event.dart";
import "package:photos/models/memory_lane/memory_lane_models.dart";

class MemoryLaneChangedEvent extends Event {
  final String personId;
  final MemoryLaneStatus status;

  MemoryLaneChangedEvent({required this.personId, required this.status});

  bool get isReady => status == MemoryLaneStatus.ready;

  @override
  String get reason =>
      '$runtimeType{personId: $personId, status: ${status.name}}';
}
