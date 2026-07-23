import "dart:convert";

import "package:flutter/foundation.dart" show immutable;
import "package:photos/services/machine_learning/face_ml/face_filtering/face_filtering_constants.dart";

@immutable
class WrappedPeopleContext {
  WrappedPeopleContext({
    required List<WrappedPeopleFile> files,
    required Map<String, WrappedPersonEntry> persons,
    required Map<String, int> personFirstCaptureMicros,
    this.selfPersonID,
  }) : files = List<WrappedPeopleFile>.unmodifiable(files),
       persons = Map<String, WrappedPersonEntry>.unmodifiable(persons),
       personFirstCaptureMicros = Map<String, int>.unmodifiable(
         personFirstCaptureMicros,
       );

  factory WrappedPeopleContext.empty() {
    return WrappedPeopleContext(
      files: const <WrappedPeopleFile>[],
      persons: const <String, WrappedPersonEntry>{},
      personFirstCaptureMicros: const <String, int>{},
      selfPersonID: null,
    );
  }

  final List<WrappedPeopleFile> files;
  final Map<String, WrappedPersonEntry> persons;
  final Map<String, int> personFirstCaptureMicros;
  final String? selfPersonID;

  bool get hasPeople => files.isNotEmpty && persons.isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      "files": files.map((WrappedPeopleFile file) => file.toJson()).toList(),
      "persons": persons.map(
        (String key, WrappedPersonEntry value) => MapEntry(key, value.toJson()),
      ),
      "firstCaptureMicros": personFirstCaptureMicros,
      "selfPersonID": selfPersonID,
    };
  }

  static WrappedPeopleContext fromJson(Map<String, Object?> json) {
    final List<dynamic> rawFiles = json["files"] as List<dynamic>? ?? const [];
    final Map<String, Object?> rawPersons =
        (json["persons"] as Map?)?.cast<String, Object?>() ??
        <String, Object?>{};
    final Map<String, WrappedPersonEntry> persons =
        <String, WrappedPersonEntry>{
          for (final MapEntry<String, Object?> entry in rawPersons.entries)
            entry.key: WrappedPersonEntry.fromJson(
              (entry.value as Map).cast<String, Object?>(),
            ),
        };
    final Map<String, int> firstCaptureMicros =
        (json["firstCaptureMicros"] as Map?)?.map(
          (Object? key, Object? value) =>
              MapEntry(key?.toString() ?? "", (value as num).toInt()),
        ) ??
        <String, int>{};
    return WrappedPeopleContext(
      files: rawFiles
          .map(
            (dynamic entry) => WrappedPeopleFile.fromJson(
              (entry as Map).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
      persons: persons,
      personFirstCaptureMicros: firstCaptureMicros,
      selfPersonID: json["selfPersonID"] as String?,
    );
  }
}

@immutable
class WrappedCity {
  const WrappedCity({
    required this.name,
    required this.country,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final String country;
  final double latitude;
  final double longitude;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      "name": name,
      "country": country,
      "latitude": latitude,
      "longitude": longitude,
    };
  }

  static WrappedCity fromJson(Map<String, Object?> json) {
    return WrappedCity(
      name: json["name"] as String? ?? "",
      country: json["country"] as String? ?? "",
      latitude: (json["latitude"] as num?)?.toDouble() ?? 0.0,
      longitude: (json["longitude"] as num?)?.toDouble() ?? 0.0,
    );
  }
}

@immutable
class WrappedAestheticsContext {
  WrappedAestheticsContext({
    required Map<int, List<double>> clipEmbeddings,
    required Map<String, List<double>> textEmbeddings,
  }) : clipEmbeddings = Map<int, List<double>>.unmodifiable(
         _dedupeLists(clipEmbeddings),
       ),
       textEmbeddings = Map<String, List<double>>.unmodifiable(
         _dedupeLists(textEmbeddings),
       );

  factory WrappedAestheticsContext.empty() {
    return WrappedAestheticsContext(
      clipEmbeddings: const <int, List<double>>{},
      textEmbeddings: const <String, List<double>>{},
    );
  }

  final Map<int, List<double>> clipEmbeddings;
  final Map<String, List<double>> textEmbeddings;

  bool get hasEmbeddings => clipEmbeddings.isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      "clipEmbeddings": clipEmbeddings.map(
        (int key, List<double> value) => MapEntry(key.toString(), value),
      ),
      "textEmbeddings": textEmbeddings,
    };
  }

  static WrappedAestheticsContext fromJson(Map<String, Object?> json) {
    final Map<String, Object?> rawClip =
        (json["clipEmbeddings"] as Map?)?.cast<String, Object?>() ??
        <String, Object?>{};
    final Map<int, List<double>> clipEmbeddings = <int, List<double>>{
      for (final MapEntry<String, Object?> entry in rawClip.entries)
        int.tryParse(entry.key) ?? 0: _castToDoubleList(entry.value),
    }..removeWhere((int key, List<double> value) => key <= 0 || value.isEmpty);

    final Map<String, Object?> rawText =
        (json["textEmbeddings"] as Map?)?.cast<String, Object?>() ??
        <String, Object?>{};
    final Map<String, List<double>> textEmbeddings = <String, List<double>>{
      for (final MapEntry<String, Object?> entry in rawText.entries)
        entry.key: _castToDoubleList(entry.value),
    }..removeWhere((String key, List<double> value) => value.isEmpty);

    if (clipEmbeddings.isEmpty && textEmbeddings.isEmpty) {
      return WrappedAestheticsContext.empty();
    }

    return WrappedAestheticsContext(
      clipEmbeddings: clipEmbeddings,
      textEmbeddings: textEmbeddings,
    );
  }

  static Map<K, List<double>> _dedupeLists<K>(Map<K, List<double>> source) {
    final Map<K, List<double>> result = <K, List<double>>{};
    source.forEach((K key, List<double> value) {
      result[key] = List<double>.from(value, growable: false);
    });
    return result;
  }

  static List<double> _castToDoubleList(Object? source) {
    if (source is List<double>) {
      return List<double>.from(source, growable: false);
    }
    if (source is List) {
      return List<double>.from(
        source.map((Object? e) {
          if (e is num) return e.toDouble();
          return 0.0;
        }),
      );
    }
    return const <double>[];
  }
}

@immutable
class WrappedPeopleFile {
  WrappedPeopleFile({
    required this.uploadedFileID,
    required this.captureMicros,
    required List<WrappedFaceRef> faces,
  }) : faces = List<WrappedFaceRef>.unmodifiable(faces);

  final int uploadedFileID;
  final int captureMicros;
  final List<WrappedFaceRef> faces;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      "uploadedFileID": uploadedFileID,
      "captureMicros": captureMicros,
      "faces": faces.map((WrappedFaceRef ref) => ref.toJson()).toList(),
    };
  }

  static WrappedPeopleFile fromJson(Map<String, Object?> json) {
    final List<dynamic> rawFaces =
        json["faces"] as List<dynamic>? ?? const <dynamic>[];
    return WrappedPeopleFile(
      uploadedFileID: json["uploadedFileID"] as int? ?? 0,
      captureMicros: json["captureMicros"] as int? ?? 0,
      faces: rawFaces
          .map(
            (dynamic entry) =>
                WrappedFaceRef.fromJson((entry as Map).cast<String, Object?>()),
          )
          .toList(growable: false),
    );
  }
}

@immutable
class WrappedFaceRef {
  const WrappedFaceRef({
    required this.faceID,
    required this.score,
    required this.blur,
    this.personID,
    this.clusterID,
  });

  final String faceID;
  final double score;
  final double blur;
  final String? personID;
  final String? clusterID;

  bool get isHighQuality =>
      score > kMinimumQualityFaceScore && blur >= kLaplacianHardThreshold;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      "faceID": faceID,
      "score": score,
      "blur": blur,
      "personID": personID,
      "clusterID": clusterID,
    };
  }

  static WrappedFaceRef fromJson(Map<String, Object?> json) {
    return WrappedFaceRef(
      faceID: json["faceID"] as String? ?? "",
      score: (json["score"] as num?)?.toDouble() ?? 0.0,
      blur: (json["blur"] as num?)?.toDouble() ?? 0.0,
      personID: json["personID"] as String?,
      clusterID: json["clusterID"] as String?,
    );
  }
}

@immutable
class WrappedPersonEntry {
  WrappedPersonEntry({
    required this.personID,
    required this.displayName,
    required this.isHidden,
    required Map<String, int> clusterFaceCounts,
    this.isMe = false,
  }) : clusterFaceCounts = Map<String, int>.unmodifiable(clusterFaceCounts);

  final String personID;
  final String displayName;
  final bool isHidden;
  final Map<String, int> clusterFaceCounts;
  final bool isMe;

  int get totalClusterFaceCount {
    int sum = 0;
    for (final int value in clusterFaceCounts.values) {
      sum += value;
    }
    return sum;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      "personID": personID,
      "displayName": displayName,
      "isHidden": isHidden,
      "clusterFaceCounts": clusterFaceCounts,
      "isMe": isMe,
    };
  }

  static WrappedPersonEntry fromJson(Map<String, Object?> json) {
    final Map<String, int> clusterFaceCounts =
        (json["clusterFaceCounts"] as Map?)?.map(
          (Object? key, Object? value) =>
              MapEntry(key?.toString() ?? "", (value as num).toInt()),
        ) ??
        <String, int>{};
    return WrappedPersonEntry(
      personID: json["personID"] as String? ?? "",
      displayName: json["displayName"] as String? ?? "",
      isHidden: json["isHidden"] as bool? ?? false,
      clusterFaceCounts: clusterFaceCounts,
      isMe: json["isMe"] as bool? ?? false,
    );
  }
}

/// Sentinel value used in heatmap grids when a day should be hidden but space
/// must still be reserved (e.g. future dates).
const int kWrappedHeatmapFutureValue = -2;

/// Sentinel value used when a day is outside the display window but we still
/// want to render a faint placeholder (e.g. padded weeks).
const int kWrappedHeatmapPaddedValue = -1;

@immutable
class WrappedResult {
  WrappedResult({
    required List<WrappedCard> cards,
    required this.year,
    required DateTime generatedAt,
    this.badgeKey,
  }) : cards = List<WrappedCard>.unmodifiable(cards),
       generatedAt = generatedAt.toUtc();

  final List<WrappedCard> cards;
  final int year;
  final DateTime generatedAt;
  final String? badgeKey;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      "year": year,
      "badgeKey": badgeKey,
      "generatedAt": generatedAt.toIso8601String(),
      "cards": cards.map((WrappedCard card) => card.toJson()).toList(),
    };
  }

  static WrappedResult fromJson(Map<String, Object?> json) {
    final List<dynamic> rawCards = json["cards"] as List<dynamic>? ?? const [];
    final DateTime generatedAt = _parseGeneratedAt(json);
    return WrappedResult(
      cards: rawCards
          .map(
            (dynamic entry) =>
                WrappedCard.fromJson((entry as Map).cast<String, Object?>()),
          )
          .toList(growable: false),
      year: json["year"] as int? ?? DateTime.now().year,
      generatedAt: generatedAt,
      badgeKey: json["badgeKey"] as String?,
    );
  }

  static WrappedResult? decode(String source) {
    if (source.isEmpty) {
      return null;
    }
    final Object? decoded = jsonDecode(source);
    if (decoded is! Map) {
      return null;
    }
    final Map<String, Object?> data = Map<String, Object?>.from(decoded);
    return WrappedResult.fromJson(data);
  }

  String encode() {
    return jsonEncode(toJson());
  }

  static DateTime _parseGeneratedAt(Map<String, Object?> json) {
    final String? rawIso = json["generatedAt"] as String?;
    if (rawIso != null && rawIso.isNotEmpty) {
      final DateTime? parsed = DateTime.tryParse(rawIso);
      if (parsed != null) {
        return parsed.toUtc();
      }
    }
    final int micros =
        (json["generatedAtMicros"] as num?)?.toInt() ?? 0; // legacy fallback
    if (micros > 0) {
      return DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }
}

@immutable
class WrappedCard {
  WrappedCard({
    required this.type,
    required this.title,
    this.subtitle,
    List<MediaRef> media = const <MediaRef>[],
    Map<String, Object?> meta = const <String, Object?>{},
  }) : media = List<MediaRef>.unmodifiable(media),
       meta = Map<String, Object?>.unmodifiable(meta);

  final WrappedCardType type;
  final String title;
  final String? subtitle;
  final List<MediaRef> media;
  final Map<String, Object?> meta;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      "type": type.name,
      "title": title,
      "subtitle": subtitle,
      "media": media.map((MediaRef ref) => ref.toJson()).toList(),
      "meta": meta,
    };
  }

  static WrappedCard fromJson(Map<String, Object?> json) {
    final String? typeName = json["type"] as String?;
    final WrappedCardType cardType = WrappedCardType.values.firstWhere(
      (WrappedCardType value) => value.name == typeName,
      orElse: () => WrappedCardType.statsTotals,
    );

    final List<dynamic> rawMedia = json["media"] as List<dynamic>? ?? const [];
    final List<MediaRef> mediaRefs = rawMedia
        .map(
          (dynamic entry) =>
              MediaRef.fromJson((entry as Map).cast<String, Object?>()),
        )
        .toList(growable: false);

    final Map<String, Object?> meta =
        (json["meta"] as Map?)?.cast<String, Object?>() ?? <String, Object?>{};

    return WrappedCard(
      type: cardType,
      title: json["title"] as String? ?? "",
      subtitle: json["subtitle"] as String?,
      media: mediaRefs,
      meta: meta,
    );
  }
}

@immutable
class MediaRef {
  const MediaRef(this.uploadedFileID);

  final int uploadedFileID;

  Map<String, Object?> toJson() {
    return <String, Object?>{"uploadedFileID": uploadedFileID};
  }

  static MediaRef fromJson(Map<String, Object?> json) {
    return MediaRef(json["uploadedFileID"] as int? ?? 0);
  }
}

enum WrappedCardType {
  statsTotals,
  statsVelocity,
  statsHeatmap,
  busiestDay,
  longestStreak,
  longestGap,
  topPerson,
  topThreePeople,
  groupVsSolo,
  newFaces,
  newPlaces,
  topCities,
  mostVisitedSpot,
  thenAndNow,
  yearInColor,
  monochrome,
  blurryFaces,
  biggestShot,
  top9Wow,
  favorites,
  albums,
  topEvents,
  bestOf25,
  badge,
  badgeDebug,
}
