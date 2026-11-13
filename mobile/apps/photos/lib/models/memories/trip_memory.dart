import "package:ente_strings/ente_strings.dart";
import "package:photos/models/location/location.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/smart_memory.dart";

class TripMemory extends SmartMemory {
  static final _baseNamePattern = RegExp(
    r"(^Base \(|\(Base, )(current|old)\)$",
  );

  final Location location;
  final String? tripKey;

  String? locationName;
  int? tripYear;

  TripMemory(
    List<Memory> memories,
    int firstDateToShow,
    int lastDateToShow,
    this.location, {
    super.id,
    this.locationName,
    this.tripYear,
    this.tripKey,
    super.firstCreationTime,
    super.lastCreationTime,
    super.capMemories,
  }) : super(memories, MemoryType.trips, '', firstDateToShow, lastDateToShow);

  static String baseName(String? place, {required bool isCurrent}) {
    final status = isCurrent ? "current" : "old";
    return place == null ? "Base ($status)" : "$place (Base, $status)";
  }

  bool get isBase =>
      locationName != null && _baseNamePattern.hasMatch(locationName!);

  TripMemory copyWith({
    List<Memory>? memories,
    int? firstDateToShow,
    int? lastDateToShow,
    String? locationName,
    int? tripYear,
    String? tripKey,
  }) {
    return TripMemory(
      memories ?? this.memories,
      firstDateToShow ?? this.firstDateToShow,
      lastDateToShow ?? this.lastDateToShow,
      location,
      id: id,
      locationName: locationName ?? this.locationName,
      tripYear: tripYear ?? this.tripYear,
      tripKey: tripKey ?? this.tripKey,
      firstCreationTime: firstCreationTime,
      lastCreationTime: lastCreationTime,
    );
  }

  @override
  String createTitle(StringsLocalizations locals, String languageCode) {
    assert(locationName != null || tripYear != null);
    if (locationName != null) {
      if (isBase) return locationName!;
      return locals.tripToLocation(location: locationName!);
    }
    if (tripYear != null) {
      if (tripYear == DateTime.now().year - 1) {
        return locals.lastYearsTrip;
      } else {
        return locals.tripInYear(year: tripYear!);
      }
    }
    throw ArgumentError("TripMemory must have a location name or trip year");
  }
}
