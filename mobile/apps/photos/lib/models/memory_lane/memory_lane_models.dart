import "dart:convert";

enum MemoryLaneStatus { ready, ineligible }

MemoryLaneStatus memoryLaneStatusFromString(String value) {
  switch (value) {
    case "ready":
      return MemoryLaneStatus.ready;
    case "ineligible":
      return MemoryLaneStatus.ineligible;
    default:
      throw ArgumentError.value(value, "value", "Unsupported timeline status");
  }
}

String memoryLaneStatusToString(MemoryLaneStatus status) {
  switch (status) {
    case MemoryLaneStatus.ready:
      return "ready";
    case MemoryLaneStatus.ineligible:
      return "ineligible";
  }
}

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
  final MemoryLaneStatus status;
  final int updatedAtMicros;
  final List<MemoryLaneEntry> entries;

  const MemoryLanePersonTimeline({
    required this.personId,
    required this.status,
    required this.updatedAtMicros,
    required this.entries,
  });

  bool get isReady => status == MemoryLaneStatus.ready;

  Map<String, dynamic> toJson() => {
    "personId": personId,
    "status": memoryLaneStatusToString(status),
    "updatedAt": updatedAtMicros,
    "entries": entries.map((entry) => entry.toJson()).toList(),
  };

  factory MemoryLanePersonTimeline.fromJson(Map<String, dynamic> json) {
    final Iterable entriesJson = json["entries"] as Iterable? ?? [];
    return MemoryLanePersonTimeline(
      personId: json["personId"] as String,
      status: memoryLaneStatusFromString(json["status"] as String),
      updatedAtMicros: json["updatedAt"] as int,
      entries: entriesJson
          .map(
            (entry) => MemoryLaneEntry.fromJson(entry as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }

  MemoryLanePersonTimeline copyWith({
    MemoryLaneStatus? status,
    int? updatedAtMicros,
    List<MemoryLaneEntry>? entries,
  }) {
    return MemoryLanePersonTimeline(
      personId: personId,
      status: status ?? this.status,
      updatedAtMicros: updatedAtMicros ?? this.updatedAtMicros,
      entries: entries ?? this.entries,
    );
  }
}

class MemoryLaneComputeLogEntry {
  final String personId;
  final String? name;
  final String? birthDate;
  final int faceCount;
  final int lastComputedMicros;
  final int logicVersion;

  const MemoryLaneComputeLogEntry({
    required this.personId,
    required this.faceCount,
    required this.lastComputedMicros,
    required this.logicVersion,
    this.name,
    this.birthDate,
  });

  Map<String, dynamic> toJson() => {
    "personId": personId,
    "name": name,
    "birthDate": birthDate,
    "faceCount": faceCount,
    "lastComputed": lastComputedMicros,
    "logicVersion": logicVersion,
  };

  factory MemoryLaneComputeLogEntry.fromJson(Map<String, dynamic> json) {
    return MemoryLaneComputeLogEntry(
      personId: json["personId"] as String,
      name: json["name"] as String?,
      birthDate: json["birthDate"] as String?,
      faceCount: json["faceCount"] as int? ?? 0,
      lastComputedMicros: json["lastComputed"] as int? ?? 0,
      logicVersion: json["logicVersion"] as int? ?? 0,
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

  const MemoryLaneCachePayload({
    required this.version,
    required this.timelines,
    required this.computeLogVersion,
    required this.computeLog,
  });

  MemoryLaneCachePayload.empty()
    : version = currentVersion,
      timelines = {},
      computeLogVersion = currentComputeLogVersion,
      computeLog = {};

  Map<String, dynamic> toJson() => {
    "version": version,
    "people": timelines.map((key, value) => MapEntry(key, value.toJson())),
    "computeLogVersion": computeLogVersion,
    "computeLog": computeLog.map((key, value) => MapEntry(key, value.toJson())),
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
    );
  }

  MemoryLaneCachePayload copyWithoutPerson(String personId) {
    final updatedTimelines = Map<String, MemoryLanePersonTimeline>.from(
      timelines,
    )..remove(personId);
    final updatedLog = Map<String, MemoryLaneComputeLogEntry>.from(computeLog)
      ..remove(personId);
    return MemoryLaneCachePayload(
      version: version,
      timelines: updatedTimelines,
      computeLogVersion: computeLogVersion,
      computeLog: updatedLog,
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
    return MemoryLaneCachePayload(
      version: jsonVersion,
      timelines: timelines,
      computeLogVersion: computeLogVersion,
      computeLog: computeLog,
    );
  }
}
