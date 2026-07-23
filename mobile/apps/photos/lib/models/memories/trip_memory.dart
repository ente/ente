import "package:photos/generated/l10n.dart";
import "package:photos/models/location/location.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/smart_memory.dart";

class TripMemory extends SmartMemory {
  final Location location;
  final String? tripKey;

  // Stuff for the title
  String? locationName;
  int? tripYear;

  TripMemory(
    List<Memory> memories,
    int firstDateToShow,
    int lastDateToShow,
    this.location, {
    String? id,
    this.locationName,
    this.tripYear,
    this.tripKey,
    super.firstCreationTime,
    super.lastCreationTime,
  }) : super(
         memories,
         MemoryType.trips,
         '',
         firstDateToShow,
         lastDateToShow,
         id: id,
       );

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
  String createTitle(AppLocalizations locals, String languageCode) {
    assert(locationName != null || tripYear != null);
    if (locationName != null) {
      if (locationName!.toLowerCase().contains("base")) return locationName!;
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
