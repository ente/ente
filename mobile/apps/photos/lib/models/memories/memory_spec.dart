import "package:photos/models/location/location.dart";
import "package:photos/models/memories/clip_memory.dart";
import "package:photos/models/memories/filler_memory.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/on_this_day_memory.dart";
import "package:photos/models/memories/people_memory.dart";
import "package:photos/models/memories/smart_memory.dart";
import "package:photos/models/memories/time_memory.dart";
import "package:photos/models/memories/trip_memory.dart";

abstract class MemorySpec {
  const MemorySpec();

  String get kind;

  MemoryType get type;

  SmartMemory toSmartMemory(
    List<Memory> memories, {
    required int firstDateToShow,
    required int lastDateToShow,
    required String title,
    required String id,
  });

  Map<String, dynamic> toJson();

  static MemorySpec? fromSmartMemory(SmartMemory memory) {
    if (memory is PeopleMemory) {
      return PeopleMemorySpec(
        personID: memory.personID,
        personName: memory.personName,
        isUnnamedCluster: memory.isUnnamedCluster,
        isBirthday: memory.isBirthday,
        newAge: memory.newAge,
        peopleMemoryType: memory.peopleMemoryType,
        activity: memory.activity,
      );
    }
    if (memory is TripMemory) {
      return TripMemorySpec(
        location: memory.location,
        locationName: memory.locationName,
        tripYear: memory.tripYear,
        tripKey: memory.tripKey,
      );
    }
    if (memory is ClipMemory) {
      return ClipMemorySpec(memory.clipMemoryType);
    }
    if (memory is TimeMemory) {
      return TimeMemorySpec(
        timeKind: memory.kind,
        day: memory.day,
        month: memory.month,
        yearsAgo: memory.yearsAgo,
      );
    }
    if (memory is FillerMemory) {
      return FillerMemorySpec(memory.yearsAgo);
    }
    if (memory is OnThisDayMemory) {
      return const OnThisDayMemorySpec();
    }
    return null;
  }

  static MemorySpec? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final kind = json["kind"] as String?;
    switch (kind) {
      case PeopleMemorySpec.kindValue:
        return PeopleMemorySpec.fromJson(json);
      case TripMemorySpec.kindValue:
        return TripMemorySpec.fromJson(json);
      case ClipMemorySpec.kindValue:
        return ClipMemorySpec.fromJson(json);
      case TimeMemorySpec.kindValue:
        return TimeMemorySpec.fromJson(json);
      case FillerMemorySpec.kindValue:
        return FillerMemorySpec.fromJson(json);
      case OnThisDayMemorySpec.kindValue:
        return const OnThisDayMemorySpec();
      default:
        return null;
    }
  }
}

class PeopleMemorySpec extends MemorySpec {
  static const kindValue = "people";

  final String personID;
  final String? personName;
  final bool isUnnamedCluster;
  final bool? isBirthday;
  final int? newAge;
  final PeopleMemoryType peopleMemoryType;
  final PeopleActivity? activity;

  const PeopleMemorySpec({
    required this.personID,
    required this.personName,
    required this.isUnnamedCluster,
    required this.isBirthday,
    required this.newAge,
    required this.peopleMemoryType,
    required this.activity,
  });

  factory PeopleMemorySpec.fromJson(Map<String, dynamic> json) {
    return PeopleMemorySpec(
      personID: json["personID"] as String,
      personName: json["personName"] as String?,
      isUnnamedCluster: json["isUnnamedCluster"] as bool? ?? false,
      isBirthday: json["isBirthday"] as bool?,
      newAge: json["newAge"] as int?,
      peopleMemoryType: peopleMemoryTypeFromString(
        json["peopleMemoryType"] as String,
      ),
      activity: json["activity"] != null
          ? PeopleActivity.values.byName(json["activity"] as String)
          : null,
    );
  }

  @override
  String get kind => kindValue;

  @override
  MemoryType get type => MemoryType.people;

  @override
  SmartMemory toSmartMemory(
    List<Memory> memories, {
    required int firstDateToShow,
    required int lastDateToShow,
    required String title,
    required String id,
  }) {
    return PeopleMemory(
      memories,
      firstDateToShow,
      lastDateToShow,
      peopleMemoryType,
      personID,
      personName,
      title: title,
      id: id,
      activity: activity,
      isUnnamedCluster: isUnnamedCluster,
      isBirthday: isBirthday,
      newAge: newAge,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      "kind": kind,
      "personID": personID,
      "personName": personName,
      "isUnnamedCluster": isUnnamedCluster,
      "isBirthday": isBirthday,
      "newAge": newAge,
      "peopleMemoryType": peopleMemoryType.name,
      "activity": activity?.name,
    };
  }
}

class TripMemorySpec extends MemorySpec {
  static const kindValue = "trip";

  final Location location;
  final String? locationName;
  final int? tripYear;
  final String? tripKey;

  const TripMemorySpec({
    required this.location,
    required this.locationName,
    required this.tripYear,
    required this.tripKey,
  });

  factory TripMemorySpec.fromJson(Map<String, dynamic> json) {
    final location = Map<String, dynamic>.from(json["location"] as Map);
    return TripMemorySpec(
      location: Location(
        latitude: location["latitude"] as double?,
        longitude: location["longitude"] as double?,
      ),
      locationName: json["locationName"] as String?,
      tripYear: json["tripYear"] as int?,
      tripKey: json["tripKey"] as String?,
    );
  }

  @override
  String get kind => kindValue;

  @override
  MemoryType get type => MemoryType.trips;

  @override
  SmartMemory toSmartMemory(
    List<Memory> memories, {
    required int firstDateToShow,
    required int lastDateToShow,
    required String title,
    required String id,
  }) {
    final tripMemory = TripMemory(
      memories,
      firstDateToShow,
      lastDateToShow,
      location,
      id: id,
      locationName: locationName,
      tripYear: tripYear,
      tripKey: tripKey,
    );
    tripMemory.title = title;
    return tripMemory;
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      "kind": kind,
      "location": {
        "latitude": location.latitude,
        "longitude": location.longitude,
      },
      "locationName": locationName,
      "tripYear": tripYear,
      "tripKey": tripKey,
    };
  }
}

class ClipMemorySpec extends MemorySpec {
  static const kindValue = "clip";

  final ClipMemoryType clipMemoryType;

  const ClipMemorySpec(this.clipMemoryType);

  factory ClipMemorySpec.fromJson(Map<String, dynamic> json) {
    return ClipMemorySpec(
      clipMemoryTypeFromString(json["clipMemoryType"] as String),
    );
  }

  @override
  String get kind => kindValue;

  @override
  MemoryType get type => MemoryType.clip;

  @override
  SmartMemory toSmartMemory(
    List<Memory> memories, {
    required int firstDateToShow,
    required int lastDateToShow,
    required String title,
    required String id,
  }) {
    final clipMemory = ClipMemory(
      memories,
      firstDateToShow,
      lastDateToShow,
      clipMemoryType,
    );
    clipMemory.title = title;
    return clipMemory;
  }

  @override
  Map<String, dynamic> toJson() {
    return {"kind": kind, "clipMemoryType": clipMemoryType.name};
  }
}

class TimeMemorySpec extends MemorySpec {
  static const kindValue = "time";

  final TimeMemoryKind timeKind;
  final DateTime? day;
  final DateTime? month;
  final int? yearsAgo;

  const TimeMemorySpec({
    required this.timeKind,
    required this.day,
    required this.month,
    required this.yearsAgo,
  });

  factory TimeMemorySpec.fromJson(Map<String, dynamic> json) {
    final day = json["day"] != null
        ? DateTime.fromMicrosecondsSinceEpoch(json["day"] as int)
        : null;
    final month = json["month"] != null
        ? DateTime.fromMicrosecondsSinceEpoch(json["month"] as int)
        : null;
    return TimeMemorySpec(
      timeKind: json["timeKind"] != null
          ? TimeMemoryKind.values.byName(json["timeKind"] as String)
          : TimeMemory.inferKind(day: day, month: month),
      day: day,
      month: month,
      yearsAgo: json["yearsAgo"] as int?,
    );
  }

  @override
  String get kind => kindValue;

  @override
  MemoryType get type => MemoryType.time;

  @override
  SmartMemory toSmartMemory(
    List<Memory> memories, {
    required int firstDateToShow,
    required int lastDateToShow,
    required String title,
    required String id,
  }) {
    final timeMemory = TimeMemory(
      memories,
      firstDateToShow,
      lastDateToShow,
      id: id,
      kind: timeKind,
      day: day,
      month: month,
      yearsAgo: yearsAgo,
    );
    timeMemory.title = title;
    return timeMemory;
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      "kind": kind,
      "timeKind": timeKind.name,
      "day": day?.microsecondsSinceEpoch,
      "month": month?.microsecondsSinceEpoch,
      "yearsAgo": yearsAgo,
    };
  }
}

class FillerMemorySpec extends MemorySpec {
  static const kindValue = "filler";

  final int yearsAgo;

  const FillerMemorySpec(this.yearsAgo);

  factory FillerMemorySpec.fromJson(Map<String, dynamic> json) {
    return FillerMemorySpec(json["yearsAgo"] as int);
  }

  @override
  String get kind => kindValue;

  @override
  MemoryType get type => MemoryType.filler;

  @override
  SmartMemory toSmartMemory(
    List<Memory> memories, {
    required int firstDateToShow,
    required int lastDateToShow,
    required String title,
    required String id,
  }) {
    final fillerMemory = FillerMemory(
      memories,
      yearsAgo,
      firstDateToShow,
      lastDateToShow,
      id: id,
    );
    fillerMemory.title = title;
    return fillerMemory;
  }

  @override
  Map<String, dynamic> toJson() {
    return {"kind": kind, "yearsAgo": yearsAgo};
  }
}

class OnThisDayMemorySpec extends MemorySpec {
  static const kindValue = "onThisDay";

  const OnThisDayMemorySpec();

  @override
  String get kind => kindValue;

  @override
  MemoryType get type => MemoryType.onThisDay;

  @override
  SmartMemory toSmartMemory(
    List<Memory> memories, {
    required int firstDateToShow,
    required int lastDateToShow,
    required String title,
    required String id,
  }) {
    final onThisDayMemory = OnThisDayMemory(
      memories,
      firstDateToShow,
      lastDateToShow,
      id: id,
    );
    onThisDayMemory.title = title;
    return onThisDayMemory;
  }

  @override
  Map<String, dynamic> toJson() {
    return {"kind": kind};
  }
}
