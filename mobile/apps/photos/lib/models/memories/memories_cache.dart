import "dart:convert";

import "package:photos/models/base/id.dart";
import "package:photos/models/base_location.dart";
import "package:photos/models/location/location.dart";
import "package:photos/models/memories/clip_memory.dart";
import "package:photos/models/memories/memory.dart";
import "package:photos/models/memories/memory_spec.dart";
import "package:photos/models/memories/people_memory.dart";
import "package:photos/models/memories/smart_memory.dart";
import "package:photos/models/memories/smart_memory_constants.dart";
import "package:photos/models/memories/trip_memory.dart";

const kPersonShowTimeout = Duration(days: 16 * kMemoriesUpdateFrequencyDays);
const kClipShowTimeout = Duration(days: 10 * kMemoriesUpdateFrequencyDays);
const kTripShowTimeout = Duration(days: 40 * kMemoriesUpdateFrequencyDays);

final maxShowTimeout =
    [
      kPersonShowTimeout,
      kTripShowTimeout,
    ].reduce((value, element) => value > element ? value : element) *
    3;

class MemoriesCache {
  final List<ToShowMemory> toShowMemories;
  final List<PeopleShownLog> peopleShownLogs;
  final List<ClipShownLog> clipShownLogs;
  final List<TripsShownLog> tripsShownLogs;
  final List<BaseLocation> baseLocations;

  MemoriesCache({
    required this.toShowMemories,
    required this.peopleShownLogs,
    required this.clipShownLogs,
    required this.tripsShownLogs,
    required this.baseLocations,
  });

  factory MemoriesCache.fromJson(Map<String, dynamic> json) {
    return MemoriesCache(
      toShowMemories: ToShowMemory.decodeJsonToList(json['toShowMemories']),
      peopleShownLogs: PeopleShownLog.decodeJsonToList(json['peopleShownLogs']),
      clipShownLogs: ClipShownLog.decodeJsonToList(json['clipShownLogs']),
      tripsShownLogs: TripsShownLog.decodeJsonToList(json['tripsShownLogs']),
      baseLocations: json['baseLocations'] != null
          ? BaseLocation.decodeJsonToList(json['baseLocations'])
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'toShowMemories': ToShowMemory.encodeListToJson(toShowMemories),
      'peopleShownLogs': PeopleShownLog.encodeListToJson(peopleShownLogs),
      'clipShownLogs': ClipShownLog.encodeListToJson(clipShownLogs),
      'tripsShownLogs': TripsShownLog.encodeListToJson(tripsShownLogs),
      'baseLocations': BaseLocation.encodeListToJson(baseLocations),
    };
  }

  static String encodeToJsonString(MemoriesCache cache) {
    return jsonEncode(cache.toJson());
  }

  static MemoriesCache decodeFromJsonString(String jsonString) {
    return MemoriesCache.fromJson(jsonDecode(jsonString));
  }
}

class ToShowMemory {
  final String title;
  final List<int> fileUploadedIDs;
  final List<int>? fileLocalIntIDs;
  final MemoryType type;
  final int firstTimeToShow;
  final int lastTimeToShow;
  final int calculationTime;
  final String id;

  final String? personID;
  final String? personName;
  final bool? isUnnamedCluster;
  final bool? isBirthday;
  final PeopleMemoryType? peopleMemoryType;
  final ClipMemoryType? clipMemoryType;
  final Location? location;
  final MemorySpec? spec;

  bool get isOld {
    final now = DateTime.now().microsecondsSinceEpoch;
    return now > lastTimeToShow;
  }

  bool isRelevantAt(int timestamp) {
    return timestamp >= firstTimeToShow && timestamp < lastTimeToShow;
  }

  bool shouldShowNow() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final relevantForNow = isRelevantAt(now);
    final calculatedForNow =
        (now >= calculationTime) &&
        (now < calculationTime + kMemoriesUpdateFrequency.inMicroseconds);
    return relevantForNow &&
        (calculatedForNow ||
            type == MemoryType.onThisDay ||
            type == MemoryType.trips);
  }

  ToShowMemory(
    this.title,
    this.fileUploadedIDs,
    this.type,
    this.firstTimeToShow,
    this.lastTimeToShow,
    this.id,
    this.calculationTime, {
    this.fileLocalIntIDs,
    this.personID,
    this.personName,
    this.isUnnamedCluster,
    this.isBirthday,
    this.peopleMemoryType,
    this.clipMemoryType,
    this.location,
    this.spec,
  }) : assert(
         (spec != null) ||
             (type == MemoryType.people &&
                 personID != null &&
                 peopleMemoryType != null) ||
             (type == MemoryType.trips && location != null) ||
             (type == MemoryType.clip && clipMemoryType != null) ||
             (type != MemoryType.people &&
                 type != MemoryType.trips &&
                 type != MemoryType.clip),
         "PersonID and peopleMemoryType must be provided for people memory type, and location must be provided for trips memory type",
       );

  factory ToShowMemory.fromSmartMemory(
    SmartMemory memory,
    DateTime calcTime, {
    List<int>? fileLocalIntIDs,
  }) {
    String? personID;
    String? personName;
    bool? isUnnamedCluster;
    bool? isBirthday;
    PeopleMemoryType? peopleMemoryType;
    ClipMemoryType? clipMemoryType;
    Location? location;
    if (memory is PeopleMemory) {
      personID = memory.personID;
      personName = memory.personName;
      isUnnamedCluster = memory.isUnnamedCluster;
      isBirthday = memory.isBirthday;
      peopleMemoryType = memory.peopleMemoryType;
    } else if (memory is TripMemory) {
      location = memory.location;
    } else if (memory is ClipMemory) {
      clipMemoryType = memory.clipMemoryType;
    }
    final spec = MemorySpec.fromSmartMemory(memory);
    final fileUploadedIDs = memory.memories
        .where((m) => m.file.uploadedFileID != null)
        .map((m) => m.file.uploadedFileID!)
        .toList();
    return ToShowMemory(
      memory.title,
      fileUploadedIDs,
      memory.type,
      memory.firstDateToShow,
      memory.lastDateToShow,
      memory.id,
      calcTime.microsecondsSinceEpoch,
      fileLocalIntIDs: fileLocalIntIDs,
      personID: personID,
      personName: personName,
      isUnnamedCluster: isUnnamedCluster,
      isBirthday: isBirthday,
      peopleMemoryType: peopleMemoryType,
      clipMemoryType: clipMemoryType,
      location: location,
      spec: spec,
    );
  }

  factory ToShowMemory.fromJson(Map<String, dynamic> json) {
    final spec = MemorySpec.fromJson(
      json['spec'] != null ? Map<String, dynamic>.from(json['spec']) : null,
    );
    return ToShowMemory(
      json['title'],
      List<int>.from(json['fileUploadedIDs']),
      memoryTypeFromString(json['type']),
      json['firstTimeToShow'],
      json['lastTimeToShow'],
      json['id'] ?? newID(json['type'] as String),
      json['calculationTime'],
      fileLocalIntIDs: json['fileLocalIntIDs'] != null
          ? List<int>.from(json['fileLocalIntIDs'])
          : null,
      personID: json['personID'],
      isBirthday: json['isBirthday'],
      personName: json['personName'],
      isUnnamedCluster: json['isUnnamedCluster'],
      peopleMemoryType: json['peopleMemoryType'] != null
          ? peopleMemoryTypeFromString(json['peopleMemoryType'])
          : null,
      clipMemoryType: json['clipMemoryType'] != null
          ? clipMemoryTypeFromString(json['clipMemoryType'])
          : null,
      location: json['location'] != null
          ? Location(
              latitude: json['location']['latitude'],
              longitude: json['location']['longitude'],
            )
          : null,
      spec: spec,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'fileUploadedIDs': fileUploadedIDs.toList(),
      if (fileLocalIntIDs != null) 'fileLocalIntIDs': fileLocalIntIDs!.toList(),
      'type': type.toString().split('.').last,
      'firstTimeToShow': firstTimeToShow,
      'lastTimeToShow': lastTimeToShow,
      'id': id,
      'calculationTime': calculationTime,
      'personID': personID,
      'isBirthday': isBirthday,
      'personName': personName,
      'isUnnamedCluster': isUnnamedCluster,
      'peopleMemoryType': peopleMemoryType?.toString().split('.').last,
      'clipMemoryType': clipMemoryType?.toString().split('.').last,
      if (spec != null) 'spec': spec!.toJson(),
      'location': location != null
          ? {'latitude': location!.latitude!, 'longitude': location!.longitude!}
          : null,
    };
  }

  static String encodeListToJson(List<ToShowMemory> toShowMemories) {
    final jsonList = toShowMemories.map((memory) => memory.toJson()).toList();
    return jsonEncode(jsonList);
  }

  static List<ToShowMemory> decodeJsonToList(String jsonString) {
    final jsonList = jsonDecode(jsonString) as List;
    return jsonList.map((json) => ToShowMemory.fromJson(json)).toList();
  }

  bool get hasTypedSpec => spec != null;

  String? get tripKey {
    final currentSpec = spec;
    if (currentSpec is TripMemorySpec) {
      return currentSpec.tripKey;
    }
    return null;
  }

  String get tripIdentityKey {
    final key = tripKey;
    if (key != null && key.isNotEmpty) {
      return "trip:$key";
    }
    final loc = location;
    if (loc == null) {
      return "legacy:$id";
    }
    final latitude = (loc.latitude ?? 0).toStringAsFixed(2);
    final longitude = (loc.longitude ?? 0).toStringAsFixed(2);
    return "legacy:$latitude:$longitude";
  }

  SmartMemory toSmartMemory(List<Memory> memories) {
    if (spec != null) {
      return spec!.toSmartMemory(
        memories,
        firstDateToShow: firstTimeToShow,
        lastDateToShow: lastTimeToShow,
        title: title,
        id: id,
      );
    }

    if (type == MemoryType.people) {
      return PeopleMemory(
        memories,
        firstTimeToShow,
        lastTimeToShow,
        peopleMemoryType!,
        personID!,
        personName,
        isUnnamedCluster: isUnnamedCluster ?? false,
        title: title,
        id: id,
      );
    }

    return SmartMemory(
      memories,
      type,
      title,
      firstTimeToShow,
      lastTimeToShow,
      id: id,
    );
  }
}

class PeopleShownLog {
  final String personID;
  final PeopleMemoryType peopleMemoryType;
  final int lastTimeShown;

  PeopleShownLog(this.personID, this.peopleMemoryType, this.lastTimeShown);

  factory PeopleShownLog.fromOldCacheMemory(ToShowMemory memory) {
    assert(
      memory.type == MemoryType.people &&
          memory.personID != null &&
          memory.peopleMemoryType != null,
    );
    return PeopleShownLog(
      memory.personID!,
      memory.peopleMemoryType!,
      memory.lastTimeToShow,
    );
  }

  factory PeopleShownLog.fromJson(Map<String, dynamic> json) {
    return PeopleShownLog(
      json['personID'],
      peopleMemoryTypeFromString(json['peopleMemoryType']),
      json['lastTimeShown'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'personID': personID,
      'peopleMemoryType': peopleMemoryType.toString().split('.').last,
      'lastTimeShown': lastTimeShown,
    };
  }

  static String encodeListToJson(List<PeopleShownLog> shownLogs) {
    final jsonList = shownLogs.map((log) => log.toJson()).toList();
    return jsonEncode(jsonList);
  }

  static List<PeopleShownLog> decodeJsonToList(String jsonString) {
    final jsonList = jsonDecode(jsonString) as List;
    return jsonList.map((json) => PeopleShownLog.fromJson(json)).toList();
  }
}

class ClipShownLog {
  final ClipMemoryType clipMemoryType;
  final int lastTimeShown;

  ClipShownLog(this.clipMemoryType, this.lastTimeShown);

  factory ClipShownLog.fromOldCacheMemory(ToShowMemory memory) {
    assert(memory.type == MemoryType.clip && memory.clipMemoryType != null);
    return ClipShownLog(memory.clipMemoryType!, memory.lastTimeToShow);
  }

  factory ClipShownLog.fromJson(Map<String, dynamic> json) {
    return ClipShownLog(
      clipMemoryTypeFromString(json['clipMemoryType']),
      json['lastTimeShown'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'clipMemoryType': clipMemoryType.toString().split('.').last,
      'lastTimeShown': lastTimeShown,
    };
  }

  static String encodeListToJson(List<ClipShownLog> shownLogs) {
    final jsonList = shownLogs.map((log) => log.toJson()).toList();
    return jsonEncode(jsonList);
  }

  static List<ClipShownLog> decodeJsonToList(String jsonString) {
    final jsonList = jsonDecode(jsonString) as List;
    return jsonList.map((json) => ClipShownLog.fromJson(json)).toList();
  }
}

class TripsShownLog {
  final Location location;
  final int lastTimeShown;
  final String? tripKey;

  TripsShownLog(this.location, this.lastTimeShown, this.tripKey);

  factory TripsShownLog.fromOldCacheMemory(ToShowMemory memory) {
    assert(memory.type == MemoryType.trips && memory.location != null);
    return TripsShownLog(
      memory.location!,
      memory.lastTimeToShow,
      memory.tripKey,
    );
  }

  factory TripsShownLog.fromJson(Map<String, dynamic> json) {
    return TripsShownLog(
      Location(
        latitude: json['location']['latitude'],
        longitude: json['location']['longitude'],
      ),
      json['lastTimeShown'],
      json['tripKey'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'location': {
        'latitude': location.latitude!,
        'longitude': location.longitude!,
      },
      'lastTimeShown': lastTimeShown,
      'tripKey': tripKey,
    };
  }

  static String encodeListToJson(List<TripsShownLog> shownLogs) {
    final jsonList = shownLogs.map((log) => log.toJson()).toList();
    return jsonEncode(jsonList);
  }

  static List<TripsShownLog> decodeJsonToList(String jsonString) {
    final jsonList = jsonDecode(jsonString) as List;
    return jsonList.map((json) => TripsShownLog.fromJson(json)).toList();
  }
}
