import "package:photos/generated/l10n.dart";
import "package:photos/models/base/id.dart";
import "package:photos/models/memories/memory.dart";

enum MemoryType { people, trips, clip, time, filler, onThisDay }

const int kMaxSmartMemoryItems = 100;

MemoryType memoryTypeFromString(String type) {
  switch (type) {
    case "people":
      return MemoryType.people;
    case "trips":
      return MemoryType.trips;
    case "time":
      return MemoryType.time;
    case "filler":
      return MemoryType.filler;
    case "clip":
      return MemoryType.clip;
    case "onThisDay":
      return MemoryType.onThisDay;
    default:
      throw ArgumentError("Invalid memory type: $type");
  }
}

class SmartMemory {
  final List<Memory> memories;
  final MemoryType type;
  String title;
  int firstDateToShow;
  int lastDateToShow;
  late final String id;

  int? firstCreationTime;
  int? lastCreationTime;

  SmartMemory(
    List<Memory> memories,
    this.type,
    this.title,
    this.firstDateToShow,
    this.lastDateToShow, {
    String? id,
    this.firstCreationTime,
    this.lastCreationTime,
  }) : memories = _capMemories(memories) {
    this.id = id ?? newID(type.name);
  }

  static List<Memory> _capMemories(List<Memory> memories) {
    if (memories.length <= kMaxSmartMemoryItems) {
      return memories;
    }
    return memories.take(kMaxSmartMemoryItems).toList();
  }

  bool get notForShow => firstDateToShow == 0 && lastDateToShow == 0;

  bool isOld() {
    return lastDateToShow < DateTime.now().microsecondsSinceEpoch;
  }

  bool shouldShowNow() {
    final int now = DateTime.now().microsecondsSinceEpoch;
    return now >= firstDateToShow && now <= lastDateToShow;
  }

  String createTitle(AppLocalizations locals, String languageCode) {
    throw UnimplementedError("createTitle must be implemented in subclass");
  }

  int averageCreationTime() {
    if (firstCreationTime != null && lastCreationTime != null) {
      return (firstCreationTime! + lastCreationTime!) ~/ 2;
    }
    final List<int> creationTimes = memories
        .where((memory) => memory.file.creationTime != null)
        .map((memory) => memory.file.creationTime!)
        .toList();
    if (creationTimes.length < 2) {
      if (creationTimes.isEmpty) {
        firstCreationTime = 0;
        lastCreationTime = 0;
        return 0;
      }
      return creationTimes.isEmpty ? 0 : creationTimes.first;
    }
    creationTimes.sort();
    firstCreationTime ??= creationTimes.first;
    lastCreationTime ??= creationTimes.last;
    return (firstCreationTime! + lastCreationTime!) ~/ 2;
  }
}
