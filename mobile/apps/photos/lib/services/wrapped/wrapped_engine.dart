import "package:computer/computer.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/ml/face/face_with_embedding.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/models/ml/vector.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/favorites_service.dart";
import "package:photos/services/location_service.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/services/search_service.dart";
import "package:photos/services/text_embeddings_cache_service.dart";
import "package:photos/services/wrapped/candidate_builders.dart";
import "package:photos/services/wrapped/models.dart";

final Logger _engineLogger = Logger("WrappedEngine");
final Logger _computeLogger = Logger("WrappedEngineIsolate");

/// Orchestrates the single-isolate computation pipeline for Ente Rewind.
class WrappedEngine {
  const WrappedEngine._();

  /// Schedules the compute pipeline on a worker isolate.
  static Future<WrappedResult> compute({required int year}) async {
    final DateTime now = DateTime.now();
    _engineLogger.fine("Scheduling Wrapped compute for $year at $now");

    final _CollectedFiles collected = await _collectFilesForYear(year);
    _engineLogger.fine(
      "Collected ${collected.yearFiles.length} media items for Wrapped $year compute",
    );

    final WrappedPeopleContext peopleContext = await _collectPeopleContext(
      year: year,
      yearFiles: collected.yearFiles,
      fileByUploadedId: collected.fileByUploadedId,
    );
    final WrappedAestheticsContext aestheticsContext =
        await _collectAestheticsContext(
          year: year,
          yearFiles: collected.yearFiles,
        );
    List<WrappedCity> cities = const <WrappedCity>[];
    try {
      final List<City> loadedCities = await locationService.getCities();
      cities = <WrappedCity>[
        for (final City city in loadedCities)
          WrappedCity(
            name: city.city,
            country: city.country,
            latitude: city.lat,
            longitude: city.lng,
          ),
      ];
    } catch (error, stackTrace) {
      _engineLogger.warning(
        "Failed to load cities for Wrapped $year places context",
        error,
        stackTrace,
      );
    }

    return await Computer.shared().compute(
          _wrappedComputeIsolate,
          param: <String, Object?>{
            "year": year,
            "now": now,
            "files": collected.yearFiles,
            "people": peopleContext.toJson(),
            "aesthetics": aestheticsContext.toJson(),
            "cities": cities.map((WrappedCity city) => city.toJson()).toList(),
            "favoriteUploadedIDs": collected.favoriteUploadedIds.toList(
              growable: false,
            ),
            "archivedCollectionIDs": collected.archivedCollectionIDs.toList(
              growable: false,
            ),
          },
          taskName: "wrapped_compute_$year",
        )
        as WrappedResult;
  }

  static Future<_CollectedFiles> _collectFilesForYear(int year) async {
    final List<EnteFile> allFiles = await SearchService.instance
        .getAllFilesForSearch();
    final List<EnteFile> filtered = <EnteFile>[];
    final Map<int, EnteFile> fileByUploadedId = <int, EnteFile>{};
    for (final EnteFile file in allFiles) {
      if (!file.isOwner) {
        continue;
      }
      final int? uploadedId = file.uploadedFileID;
      if (uploadedId != null) {
        fileByUploadedId[uploadedId] = file;
      }
      final int? creationTime = file.creationTime;
      if (creationTime == null) {
        continue;
      }
      final DateTime captured = DateTime.fromMicrosecondsSinceEpoch(
        creationTime,
      );
      if (captured.year != year) {
        continue;
      }
      filtered.add(file);
    }

    filtered.sort((EnteFile a, EnteFile b) {
      final int aTime = a.creationTime ?? 0;
      final int bTime = b.creationTime ?? 0;
      if (aTime != bTime) return aTime.compareTo(bTime);
      final int aId = a.uploadedFileID ?? a.generatedID ?? 0;
      final int bId = b.uploadedFileID ?? b.generatedID ?? 0;
      return aId.compareTo(bId);
    });

    final Set<int> favoriteUploadedIds = _collectFavoriteUploadedIDs(filtered);
    final Set<int> archivedCollectionIDs = CollectionsService.instance
        .archivedOrHiddenCollectionIds();

    return _CollectedFiles(
      yearFiles: filtered,
      fileByUploadedId: fileByUploadedId,
      favoriteUploadedIds: favoriteUploadedIds,
      archivedCollectionIDs: archivedCollectionIDs,
    );
  }

  static Set<int> _collectFavoriteUploadedIDs(List<EnteFile> files) {
    final FavoritesService favoritesService = FavoritesService.instance;
    final Set<int> favorites = <int>{};
    for (final EnteFile file in files) {
      final int? uploadedID = file.uploadedFileID;
      if (uploadedID == null) {
        continue;
      }
      try {
        if (favoritesService.isFavoriteCache(file)) {
          favorites.add(uploadedID);
        }
      } catch (error, stackTrace) {
        _engineLogger.warning(
          "Failed to determine favorites status for ${file.uploadedFileID}",
          error,
          stackTrace,
        );
      }
    }
    return favorites;
  }

  static Future<WrappedPeopleContext> _collectPeopleContext({
    required int year,
    required List<EnteFile> yearFiles,
    required Map<int, EnteFile> fileByUploadedId,
  }) async {
    if (yearFiles.isEmpty) {
      return WrappedPeopleContext.empty();
    }

    final Set<int> yearFileIDs = <int>{
      for (final EnteFile file in yearFiles)
        if (file.uploadedFileID != null) file.uploadedFileID!,
    };
    if (yearFileIDs.isEmpty) {
      return WrappedPeopleContext.empty();
    }

    final Map<int, List<FaceWithoutEmbedding>> facesByFile =
        <int, List<FaceWithoutEmbedding>>{};
    try {
      final Map<int, List<FaceWithoutEmbedding>> allFaces = await MLDataDB
          .instance
          .getFileIDsToFacesWithoutEmbedding();
      if (allFaces.isNotEmpty) {
        for (final MapEntry<int, List<FaceWithoutEmbedding>> entry
            in allFaces.entries) {
          if (yearFileIDs.contains(entry.key)) {
            facesByFile[entry.key] = entry.value;
          }
        }
      }
    } catch (error, stackTrace) {
      _engineLogger.warning(
        "Failed to fetch faces for Wrapped $year people context",
        error,
        stackTrace,
      );
      return WrappedPeopleContext.empty();
    }

    final Map<String, WrappedPersonEntry> personEntries =
        <String, WrappedPersonEntry>{};
    final Map<String, int> personFirstCaptureMicros = <String, int>{};
    final Map<String, String> faceIdToPerson = <String, String>{};
    final Map<String, String> faceIdToCluster = <String, String>{};
    final String? normalizedUserEmail = Configuration.instance
        .getEmail()
        ?.trim()
        .toLowerCase();
    String? selfPersonID;

    if (PersonService.isInitialized) {
      try {
        final List<PersonEntity> persons = await PersonService.instance
            .getPersons();
        for (final PersonEntity person in persons) {
          final PersonData data = person.data;
          if (data.assigned.isEmpty) {
            continue;
          }
          final Map<String, int> clusterFaceCounts = <String, int>{};
          int? earliestMicros;
          for (final ClusterInfo cluster in data.assigned) {
            if (cluster.faces.isEmpty) {
              continue;
            }
            clusterFaceCounts[cluster.id] = cluster.faces.length;
            for (final String faceID in cluster.faces) {
              faceIdToPerson[faceID] = person.remoteID;
              faceIdToCluster[faceID] = cluster.id;
              final int? fileID = tryGetFileIdFromFaceId(faceID);
              if (fileID == null) {
                continue;
              }
              final EnteFile? file = fileByUploadedId[fileID];
              final int? captureMicros = file?.creationTime;
              if (captureMicros == null || captureMicros <= 0) {
                continue;
              }
              if (earliestMicros == null || captureMicros < earliestMicros) {
                earliestMicros = captureMicros;
              }
            }
          }
          if (clusterFaceCounts.isEmpty) {
            continue;
          }
          final String? normalizedPersonEmail = data.email
              ?.trim()
              .toLowerCase();
          final bool isMe =
              normalizedUserEmail != null &&
              normalizedPersonEmail != null &&
              normalizedPersonEmail == normalizedUserEmail;
          if (isMe) {
            selfPersonID = person.remoteID;
          }
          final bool isHidden = data.isHidden || data.hideFromMemories;
          personEntries[person.remoteID] = WrappedPersonEntry(
            personID: person.remoteID,
            displayName: data.name,
            isHidden: isHidden,
            clusterFaceCounts: clusterFaceCounts,
            isMe: isMe,
          );
          if (earliestMicros != null) {
            personFirstCaptureMicros[person.remoteID] = earliestMicros;
          }
        }
      } catch (error, stackTrace) {
        _engineLogger.warning(
          "Failed to load persons for Wrapped $year",
          error,
          stackTrace,
        );
      }
    }

    final List<WrappedPeopleFile> peopleFiles = <WrappedPeopleFile>[];
    for (final EnteFile file in yearFiles) {
      final int? uploadedFileID = file.uploadedFileID;
      if (uploadedFileID == null) {
        continue;
      }
      final List<FaceWithoutEmbedding>? faces = facesByFile[uploadedFileID];
      if (faces == null || faces.isEmpty) {
        continue;
      }
      final List<WrappedFaceRef> faceRefs = faces
          .map(
            (FaceWithoutEmbedding face) => WrappedFaceRef(
              faceID: face.faceID,
              score: face.score,
              blur: face.blur,
              personID: faceIdToPerson[face.faceID],
              clusterID: faceIdToCluster[face.faceID],
            ),
          )
          .toList(growable: false);
      if (faceRefs.isEmpty) {
        continue;
      }
      peopleFiles.add(
        WrappedPeopleFile(
          uploadedFileID: uploadedFileID,
          captureMicros: file.creationTime ?? 0,
          faces: faceRefs,
        ),
      );
    }

    if (peopleFiles.isEmpty && personEntries.isEmpty) {
      return WrappedPeopleContext.empty();
    }

    return WrappedPeopleContext(
      files: peopleFiles,
      persons: personEntries,
      personFirstCaptureMicros: personFirstCaptureMicros,
      selfPersonID: selfPersonID,
    );
  }

  static Future<WrappedAestheticsContext> _collectAestheticsContext({
    required int year,
    required List<EnteFile> yearFiles,
  }) async {
    if (yearFiles.isEmpty) {
      return WrappedAestheticsContext.empty();
    }

    final Set<int> yearFileIDs = <int>{
      for (final EnteFile file in yearFiles)
        if (file.uploadedFileID != null) file.uploadedFileID!,
    };
    if (yearFileIDs.isEmpty) {
      return WrappedAestheticsContext.empty();
    }

    final Map<int, List<double>> clipEmbeddings = <int, List<double>>{};
    try {
      final List<EmbeddingVector> vectors = await MLDataDB.instance
          .getAllClipVectors();
      for (final EmbeddingVector vector in vectors) {
        final int fileID = vector.fileID;
        if (!yearFileIDs.contains(fileID) || vector.isEmpty) {
          continue;
        }
        clipEmbeddings[fileID] = vector.vector.toList(growable: false);
      }
    } catch (error, stackTrace) {
      _engineLogger.warning(
        "Failed to collect CLIP embeddings for Wrapped $year",
        error,
        stackTrace,
      );
    }

    if (clipEmbeddings.isEmpty) {
      return WrappedAestheticsContext.empty();
    }

    final Set<String> queries = <String>{
      ...AestheticsCandidateBuilder.requiredTextQueries,
      ...WrappedBadgeSelector.requiredTextQueries,
      ...WrappedMediaSelector.requiredTextQueries,
    };
    final Map<String, List<double>> textEmbeddings = <String, List<double>>{};
    for (final String query in queries) {
      try {
        final List<double> embedding = await TextEmbeddingsCacheService.instance
            .getEmbedding(query);
        textEmbeddings[query] = List<double>.from(embedding, growable: false);
      } catch (error, stackTrace) {
        _engineLogger.warning(
          "Failed to compute text embedding for Wrapped query \"$query\"",
          error,
          stackTrace,
        );
      }
    }

    return WrappedAestheticsContext(
      clipEmbeddings: clipEmbeddings,
      textEmbeddings: textEmbeddings,
    );
  }
}

Future<WrappedResult> _wrappedComputeIsolate(Map<String, Object?> args) async {
  final int year = args["year"] as int;
  final DateTime now = args["now"] as DateTime;
  final List<EnteFile> files =
      (args["files"] as List<dynamic>? ?? const <dynamic>[]).cast<EnteFile>();
  final Map<String, Object?> peopleRaw =
      (args["people"] as Map?)?.cast<String, Object?>() ?? <String, Object?>{};
  final WrappedPeopleContext people = WrappedPeopleContext.fromJson(peopleRaw);
  final Map<String, Object?> aestheticsRaw =
      (args["aesthetics"] as Map?)?.cast<String, Object?>() ??
      <String, Object?>{};
  final WrappedAestheticsContext aesthetics = WrappedAestheticsContext.fromJson(
    aestheticsRaw,
  );
  final List<dynamic> rawCities =
      args["cities"] as List<dynamic>? ?? const <dynamic>[];
  final List<WrappedCity> cities = rawCities
      .map(
        (dynamic entry) =>
            WrappedCity.fromJson((entry as Map).cast<String, Object?>()),
      )
      .toList(growable: false);
  final List<dynamic> favoriteRaw =
      args["favoriteUploadedIDs"] as List<dynamic>? ?? const <dynamic>[];
  final Set<int> favoriteUploadedIds = <int>{
    for (final dynamic entry in favoriteRaw)
      if (entry is num && entry.toInt() > 0) entry.toInt(),
  };
  final List<dynamic> archivedRaw =
      args["archivedCollectionIDs"] as List<dynamic>? ?? const <dynamic>[];
  final Set<int> archivedCollectionIDs = <int>{
    for (final dynamic entry in archivedRaw)
      if (entry is num && entry.toInt() > 0) entry.toInt(),
  };

  _computeLogger.fine(
    "Wrapped compute isolate running for $year with ${files.length} media items",
  );

  final WrappedEngineContext context = WrappedEngineContext(
    year: year,
    now: now,
    files: files,
    people: people,
    aesthetics: aesthetics,
    cities: cities,
    favoriteUploadedFileIDs: favoriteUploadedIds,
    archivedCollectionIDs: archivedCollectionIDs,
  );
  final Set<int> usedMediaUploadedFileIDs = <int>{};
  final List<WrappedCard> cards = <WrappedCard>[];
  for (final WrappedCandidateBuilder builder in wrappedCandidateBuilders) {
    _computeLogger.finer("Running candidate builder ${builder.debugLabel}");
    final List<WrappedCard> builtCards = await builder.build(context);
    if (builtCards.isEmpty) {
      continue;
    }
    for (final WrappedCard card in builtCards) {
      final WrappedCard finalized = _finalizeCardMedia(
        context: context,
        card: card,
        usedMediaUploadedFileIDs: usedMediaUploadedFileIDs,
      );
      cards.add(finalized);
    }
  }

  final WrappedBadgeSelection badgeSelection = WrappedBadgeSelector.select(
    context: context,
    existingCards: cards,
  );
  final WrappedCard badgeCard = _finalizeCardMedia(
    context: context,
    card: badgeSelection.card,
    usedMediaUploadedFileIDs: usedMediaUploadedFileIDs,
  );
  final List<WrappedCard> finalCards = <WrappedCard>[...cards, badgeCard];

  return WrappedResult(
    cards: finalCards,
    year: year,
    generatedAt: now,
    badgeKey: badgeSelection.badgeKey,
  );
}

class _CollectedFiles {
  _CollectedFiles({
    required List<EnteFile> yearFiles,
    required Map<int, EnteFile> fileByUploadedId,
    required Set<int> favoriteUploadedIds,
    required Set<int> archivedCollectionIDs,
  }) : yearFiles = List<EnteFile>.unmodifiable(yearFiles),
       fileByUploadedId = Map<int, EnteFile>.unmodifiable(fileByUploadedId),
       favoriteUploadedIds = Set<int>.unmodifiable(favoriteUploadedIds),
       archivedCollectionIDs = Set<int>.unmodifiable(
         archivedCollectionIDs.where((int id) => id > 0),
       );

  final List<EnteFile> yearFiles;
  final Map<int, EnteFile> fileByUploadedId;
  final Set<int> favoriteUploadedIds;
  final Set<int> archivedCollectionIDs;
}

WrappedCard _finalizeCardMedia({
  required WrappedEngineContext context,
  required WrappedCard card,
  required Set<int> usedMediaUploadedFileIDs,
}) {
  if (card.media.isEmpty) {
    return card;
  }

  final int targetCount = card.media.length;
  final List<MediaRef> updatedMedia = <MediaRef>[];
  final Set<int> seenInCard = <int>{};

  void tryAddMediaRef(MediaRef ref) {
    final int id = ref.uploadedFileID;
    if (id <= 0) {
      return;
    }
    if (!context.isSelectableUploadedFileID(id)) {
      return;
    }
    if (usedMediaUploadedFileIDs.contains(id)) {
      return;
    }
    if (!seenInCard.add(id)) {
      return;
    }
    updatedMedia.add(ref);
  }

  for (final MediaRef ref in card.media) {
    tryAddMediaRef(ref);
  }

  if (updatedMedia.length < targetCount) {
    final List<int> candidateIds = _extractCandidateUploadedFileIDs(card.meta);
    for (final int id in candidateIds) {
      if (updatedMedia.length >= targetCount) {
        break;
      }
      if (id <= 0 || seenInCard.contains(id)) {
        continue;
      }
      if (!context.isSelectableUploadedFileID(id)) {
        continue;
      }
      if (usedMediaUploadedFileIDs.contains(id)) {
        continue;
      }
      updatedMedia.add(MediaRef(id));
      seenInCard.add(id);
    }
  }

  if (updatedMedia.length < targetCount) {
    final int remaining = targetCount - updatedMedia.length;
    if (remaining > 0) {
      final List<int> fallbackPool = context.files
          .where((EnteFile file) => file.uploadedFileID != null)
          .map((EnteFile file) => file.uploadedFileID!)
          .where(
            (int id) =>
                id > 0 &&
                context.isSelectableUploadedFileID(id) &&
                !usedMediaUploadedFileIDs.contains(id) &&
                !seenInCard.contains(id),
          )
          .toList(growable: false);
      if (fallbackPool.isNotEmpty) {
        final List<int> fallbackSelection = WrappedMediaSelector.select(
          context: context,
          candidateUploadedFileIDs: fallbackPool,
          maxCount: remaining,
          avoidPreviouslySelected: true,
          reserveSelected: false,
        );
        for (final int id in fallbackSelection) {
          if (updatedMedia.length >= targetCount) {
            break;
          }
          if (id <= 0 || seenInCard.contains(id)) {
            continue;
          }
          updatedMedia.add(MediaRef(id));
          seenInCard.add(id);
        }
      }
    }
  }

  final bool mediaChanged =
      updatedMedia.length != card.media.length ||
      !_mediaListsEqual(card.media, updatedMedia);

  final WrappedCard resultCard;
  if (!mediaChanged) {
    resultCard = card;
  } else {
    final Map<String, Object?> metaCopy = Map<String, Object?>.from(card.meta);
    if (metaCopy.containsKey("uploadedFileIDs")) {
      metaCopy["uploadedFileIDs"] = updatedMedia
          .map((MediaRef ref) => ref.uploadedFileID)
          .toList(growable: false);
    }
    resultCard = WrappedCard(
      type: card.type,
      title: card.title,
      subtitle: card.subtitle,
      media: updatedMedia,
      meta: metaCopy,
    );
  }

  final List<int> finalIds = resultCard.media
      .map((MediaRef ref) => ref.uploadedFileID)
      .where((int id) => id > 0)
      .toList(growable: false);
  if (finalIds.isNotEmpty) {
    usedMediaUploadedFileIDs.addAll(finalIds);
    WrappedMediaSelector.reserveUploadedFileIDs(
      context: context,
      uploadedFileIDs: finalIds,
    );
  }

  return resultCard;
}

List<int> _extractCandidateUploadedFileIDs(Map<String, Object?> meta) {
  final Object? raw = meta["uploadedFileIDs"];
  if (raw is! List) {
    return const <int>[];
  }
  final List<int> ids = <int>[];
  for (final Object? entry in raw) {
    if (entry is int) {
      ids.add(entry);
    } else if (entry is num) {
      ids.add(entry.toInt());
    } else if (entry is String) {
      final int? parsed = int.tryParse(entry);
      if (parsed != null) {
        ids.add(parsed);
      }
    }
  }
  return ids;
}

bool _mediaListsEqual(List<MediaRef> a, List<MediaRef> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (int index = 0; index < a.length; index += 1) {
    if (a[index].uploadedFileID != b[index].uploadedFileID) {
      return false;
    }
  }
  return true;
}
