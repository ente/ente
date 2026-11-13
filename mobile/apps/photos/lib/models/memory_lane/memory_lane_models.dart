import "dart:convert";

class MemoryLaneEntry {
  final String faceId;
  final int fileId;
  final int creationTimeMicros;
  final int year;

  const MemoryLaneEntry({
    required this.faceId,
    required this.fileId,
    required this.creationTimeMicros,
    required this.year,
  });

  Map<String, dynamic> toJson() => {
    "faceId": faceId,
    "fileId": fileId,
    "creationTime": creationTimeMicros,
    "year": year,
  };

  factory MemoryLaneEntry.fromJson(Map<String, dynamic> json) {
    return MemoryLaneEntry(
      faceId: json["faceId"] as String,
      fileId: json["fileId"] as int,
      creationTimeMicros: json["creationTime"] as int,
      year: json["year"] as int,
    );
  }
}

class MemoryLanePersonTimeline {
  final String personId;
  late final bool isCluster;
  final bool isEligible;
  final int updatedAtMicros;
  final List<MemoryLaneEntry> entries;

  MemoryLanePersonTimeline({
    required this.personId,
    required this.isEligible,
    required this.updatedAtMicros,
    required this.entries,
    this.isCluster = false,
  });

  Map<String, dynamic> toJson() => {
    "personId": personId,
    "status": isEligible ? "ready" : "ineligible",
    "updatedAt": updatedAtMicros,
    "entries": entries.map((entry) => entry.toJson()).toList(),
    "isCluster": isCluster,
  };

  factory MemoryLanePersonTimeline.fromJson(Map<String, dynamic> json) {
    final Iterable entriesJson = json["entries"] as Iterable? ?? [];
    return MemoryLanePersonTimeline(
      personId: json["personId"] as String,
      isEligible: json["status"] == "ready",
      updatedAtMicros: json["updatedAt"] as int,
      entries: entriesJson
          .map(
            (entry) => MemoryLaneEntry.fromJson(entry as Map<String, dynamic>),
          )
          .toList(growable: false),
      isCluster: json['isCluster'] as bool? ?? false,
    );
  }

  MemoryLanePersonTimeline copyWith({
    bool? isEligible,
    int? updatedAtMicros,
    List<MemoryLaneEntry>? entries,
  }) {
    return MemoryLanePersonTimeline(
      personId: personId,
      isEligible: isEligible ?? this.isEligible,
      updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
      entries: entries ?? this.entries,
      isCluster: isCluster,
    );
  }
}

class MemoryLaneComputeLogEntry {
  final String personId;
  late final bool isCluster;
  final String? name;
  final String? birthDate;
  final int faceCount;
  final int lastComputedMicros;
  final int logicVersion;

  MemoryLaneComputeLogEntry({
    required this.personId,
    required this.faceCount,
    required this.lastComputedMicros,
    required this.logicVersion,
    this.name,
    this.birthDate,
    this.isCluster = false,
  });

  Map<String, dynamic> toJson() => {
    "personId": personId,
    "name": name,
    "birthDate": birthDate,
    "faceCount": faceCount,
    "lastComputed": lastComputedMicros,
    "logicVersion": logicVersion,
    "isCluster": isCluster,
  };

  factory MemoryLaneComputeLogEntry.fromJson(Map<String, dynamic> json) {
    return MemoryLaneComputeLogEntry(
      personId: json["personId"] as String,
      name: json["name"] as String?,
      birthDate: json["birthDate"] as String?,
      faceCount: json["faceCount"] as int? ?? 0,
      lastComputedMicros: json["lastComputed"] as int? ?? 0,
      logicVersion: json["logicVersion"] as int? ?? 0,
      isCluster: json["isCluster"] as bool? ?? false,
    );
  }

  MemoryLaneComputeLogEntry copyWith({
    String? name,
    String? birthDate,
    int? faceCount,
    int? lastComputedMicros,
    int? logicVersion,
  }) {
    return MemoryLaneComputeLogEntry(
      personId: personId,
      name: name ?? this.name,
      birthDate: birthDate ?? this.birthDate,
      faceCount: faceCount ?? this.faceCount,
      lastComputedMicros: lastComputedMicros ?? this.lastComputedMicros,
      logicVersion: logicVersion ?? this.logicVersion,
      isCluster: isCluster,
    );
  }
}

class MemoryLaneSchedule {
  static const displayDuration = Duration(days: 3);

  final String personID;
  final bool isCluster;
  final int beginShowingAt;
  final int? lastCompletelySeenAt;

  const MemoryLaneSchedule({
    required this.personID,
    required this.isCluster,
    required this.beginShowingAt,
    this.lastCompletelySeenAt,
  });

  Map<String, dynamic> toJson() => {
    "personID": personID,
    "isCluster": isCluster,
    "beginShowingAt": beginShowingAt,
    "lastCompletelySeenAt": lastCompletelySeenAt,
  };

  factory MemoryLaneSchedule.fromJson(Map<String, dynamic> json) {
    return MemoryLaneSchedule(
      personID: json["personID"] as String,
      isCluster: json["isCluster"] as bool? ?? false,
      beginShowingAt: json["beginShowingAt"] as int,
      lastCompletelySeenAt: json["lastCompletelySeenAt"] as int?,
    );
  }
}

class MemoryLaneCachePayload {
  static const currentVersion = 1;
  static const currentComputeLogVersion = 1;

  final int version;
  final Map<String, MemoryLanePersonTimeline> timelines;
  final int computeLogVersion;
  final Map<String, MemoryLaneComputeLogEntry> computeLog;
  final Map<String, MemoryLaneSchedule> memoriesStripSchedule;

  const MemoryLaneCachePayload({
    required this.version,
    required this.timelines,
    required this.computeLogVersion,
    required this.computeLog,
    required this.memoriesStripSchedule,
  });

  MemoryLaneCachePayload.empty()
    : version = currentVersion,
      timelines = {},
      computeLogVersion = currentComputeLogVersion,
      computeLog = {},
      memoriesStripSchedule = {};

  Map<String, dynamic> toJson() => {
    "version": version,
    "people": timelines.map((key, value) => MapEntry(key, value.toJson())),
    "computeLogVersion": computeLogVersion,
    "computeLog": computeLog.map((key, value) => MapEntry(key, value.toJson())),
    "memoriesStripSchedule": memoriesStripSchedule.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
  };

  String toEncodedJson() => jsonEncode(toJson());

  MemoryLanePersonTimeline? operator [](String personId) => timelines[personId];

  Iterable<MemoryLanePersonTimeline> get allTimelines => timelines.values;

  MemoryLaneCachePayload copyWithTimeline(MemoryLanePersonTimeline timeline) {
    final updatedTimelines = Map<String, MemoryLanePersonTimeline>.from(
      timelines,
    );
    updatedTimelines[timeline.personId] = timeline;
    return MemoryLaneCachePayload(
      version: version,
      timelines: updatedTimelines,
      computeLogVersion: computeLogVersion,
      computeLog: computeLog,
      memoriesStripSchedule: memoriesStripSchedule,
    );
  }

  MemoryLaneCachePayload copyWithoutPerson(String personId) {
    final updatedTimelines = Map<String, MemoryLanePersonTimeline>.from(
      timelines,
    )..remove(personId);
    final updatedLog = Map<String, MemoryLaneComputeLogEntry>.from(computeLog)
      ..remove(personId);
    final updatedMemoriesStripSchedule = Map<String, MemoryLaneSchedule>.from(
      memoriesStripSchedule,
    )..remove(personId);
    return MemoryLaneCachePayload(
      version: version,
      timelines: updatedTimelines,
      computeLogVersion: computeLogVersion,
      computeLog: updatedLog,
      memoriesStripSchedule: updatedMemoriesStripSchedule,
    );
  }

  MemoryLaneCachePayload copyWithComputeLogEntry(
    MemoryLaneComputeLogEntry entry,
  ) {
    final updatedLog = Map<String, MemoryLaneComputeLogEntry>.from(computeLog);
    updatedLog[entry.personId] = entry;
    return MemoryLaneCachePayload(
      version: version,
      timelines: timelines,
      computeLogVersion: computeLogVersion,
      computeLog: updatedLog,
      memoriesStripSchedule: memoriesStripSchedule,
    );
  }

  MemoryLaneCachePayload copyWithMemoriesStripScheduleEntry(
    String timelineKey,
    MemoryLaneSchedule entry,
  ) {
    final updatedMemoriesStripSchedule = Map<String, MemoryLaneSchedule>.from(
      memoriesStripSchedule,
    );
    updatedMemoriesStripSchedule[timelineKey] = entry;
    return MemoryLaneCachePayload(
      version: version,
      timelines: timelines,
      computeLogVersion: computeLogVersion,
      computeLog: computeLog,
      memoriesStripSchedule: updatedMemoriesStripSchedule,
    );
  }

  MemoryLaneCachePayload copyWithoutMemoriesStripScheduleEntries(
    Set<String> timelineKeys,
  ) {
    final updatedMemoriesStripSchedule = Map<String, MemoryLaneSchedule>.from(
      memoriesStripSchedule,
    )..removeWhere((key, _) => timelineKeys.contains(key));
    return MemoryLaneCachePayload(
      version: version,
      timelines: timelines,
      computeLogVersion: computeLogVersion,
      computeLog: computeLog,
      memoriesStripSchedule: updatedMemoriesStripSchedule,
    );
  }

  MemoryLaneCachePayload copyWithComputeLog({
    required Map<String, MemoryLaneComputeLogEntry> entries,
    required int logVersion,
  }) {
    return MemoryLaneCachePayload(
      version: version,
      timelines: timelines,
      computeLogVersion: logVersion,
      computeLog: entries,
      memoriesStripSchedule: memoriesStripSchedule,
    );
  }

  factory MemoryLaneCachePayload.fromJson(Map<String, dynamic> json) {
    final int jsonVersion = json["version"] as int? ?? currentVersion;
    final peopleJson = json["people"] as Map<String, dynamic>? ?? {};
    final timelines = <String, MemoryLanePersonTimeline>{};
    for (final entry in peopleJson.entries) {
      timelines[entry.key] = MemoryLanePersonTimeline.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }
    final computeLogVersion =
        json["computeLogVersion"] as int? ?? currentComputeLogVersion;
    final computeLogJson = json["computeLog"] as Map<String, dynamic>? ?? {};
    final computeLog = <String, MemoryLaneComputeLogEntry>{};
    for (final entry in computeLogJson.entries) {
      computeLog[entry.key] = MemoryLaneComputeLogEntry.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }
    final memoriesStripScheduleJson =
        json["memoriesStripSchedule"] as Map<String, dynamic>? ?? {};
    final memoriesStripSchedule = <String, MemoryLaneSchedule>{};
    for (final entry in memoriesStripScheduleJson.entries) {
      memoriesStripSchedule[entry.key] = MemoryLaneSchedule.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }
    return MemoryLaneCachePayload(
      version: jsonVersion,
      timelines: timelines,
      computeLogVersion: computeLogVersion,
      computeLog: computeLog,
      memoriesStripSchedule: memoriesStripSchedule,
    );
  }
}
