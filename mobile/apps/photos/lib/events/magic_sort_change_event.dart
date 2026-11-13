import "package:photos/events/event.dart";

enum MagicSortType { mostRecent, mostRelevant }

class MagicSortChangeEvent extends Event {
  final MagicSortType sortType;
  MagicSortChangeEvent(this.sortType);
}
