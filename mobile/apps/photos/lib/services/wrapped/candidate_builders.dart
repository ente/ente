import "dart:math" as math;
import "dart:typed_data";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart" show immutable;
import "package:intl/intl.dart";
import "package:ml_linalg/dtype.dart";
import "package:ml_linalg/vector.dart";
import "package:path/path.dart" as p;
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/location/location.dart";
import "package:photos/models/metadata/common_keys.dart";
import "package:photos/services/machine_learning/face_ml/face_filtering/face_filtering_constants.dart";
import "package:photos/services/wrapped/models.dart";

part "builders/aesthetics_candidate_builder.dart";
part "builders/badge_selector.dart";
part "builders/curation_candidate_builder.dart";
part "builders/media_selector.dart";
part "builders/narrative_candidate_builder.dart";
part "builders/people_candidate_builder.dart";
part "builders/places_candidate_builder.dart";
part "builders/stats_candidate_builder.dart";

const int kWrappedSelectorCandidateCap = 1200;

List<int> limitSelectorCandidates(
  WrappedEngineContext context,
  Iterable<int> ids, {
  int? cap,
}) {
  final List<int> limited = <int>[];
  final Set<int> seen = <int>{};
  final int limit = cap ?? kWrappedSelectorCandidateCap;
  if (limit <= 0) {
    return limited;
  }
  for (final int id in ids) {
    if (id <= 0 || !seen.add(id)) {
      continue;
    }
    if (!context.isSelectableUploadedFileID(id)) {
      continue;
    }
    limited.add(id);
    if (limited.length >= limit) {
      break;
    }
  }
  return limited;
}

List<int> buildMetaUploadedIDs(List<int> candidates, int desiredCount) {
  if (candidates.isEmpty || desiredCount <= 0) {
    return const <int>[];
  }
  final int limit = math.min(desiredCount, candidates.length);
  return candidates.take(limit).toList(growable: false);
}

/// Provides basic context details for candidate builders.
@immutable
class WrappedEngineContext {
  WrappedEngineContext({
    required this.year,
    required this.now,
    required List<EnteFile> files,
    WrappedPeopleContext? people,
    WrappedAestheticsContext? aesthetics,
    List<WrappedCity>? cities,
    Set<int>? favoriteUploadedFileIDs,
    Set<int>? archivedCollectionIDs,
  }) : files = List<EnteFile>.unmodifiable(files),
       fileByUploadedID = Map<int, EnteFile>.unmodifiable(<int, EnteFile>{
         for (final EnteFile file in files)
           if (file.uploadedFileID != null) file.uploadedFileID!: file,
       }),
       people = people ?? WrappedPeopleContext.empty(),
       aesthetics = aesthetics ?? WrappedAestheticsContext.empty(),
       cities = List<WrappedCity>.unmodifiable(cities ?? const <WrappedCity>[]),
       favoriteUploadedFileIDs = Set<int>.unmodifiable(
         favoriteUploadedFileIDs ?? const <int>{},
       ),
       archivedCollectionIDs = Set<int>.unmodifiable(
         archivedCollectionIDs ?? const <int>{},
       );

  final int year;
  final DateTime now;
  final List<EnteFile> files;
  final Map<int, EnteFile> fileByUploadedID;
  final WrappedPeopleContext people;
  final WrappedAestheticsContext aesthetics;
  final List<WrappedCity> cities;
  final Set<int> favoriteUploadedFileIDs;
  final Set<int> archivedCollectionIDs;

  EnteFile? fileForUploadedID(int uploadedFileID) {
    return fileByUploadedID[uploadedFileID];
  }

  bool isSelectableUploadedFileID(int uploadedFileID) {
    final EnteFile? file = fileByUploadedID[uploadedFileID];
    if (file == null) {
      return false;
    }
    final int? collectionID = file.collectionID;
    if (collectionID != null && archivedCollectionIDs.contains(collectionID)) {
      return false;
    }
    return file.magicMetadata.visibility != archiveVisibility;
  }
}

/// Contract for producing Wrapped candidate cards for a specific domain.
abstract class WrappedCandidateBuilder {
  const WrappedCandidateBuilder();

  String get debugLabel;

  Future<List<WrappedCard>> build(WrappedEngineContext context);
}

/// Registry of all candidate builders invoked by the engine.
const List<WrappedCandidateBuilder> wrappedCandidateBuilders =
    <WrappedCandidateBuilder>[
      StatsCandidateBuilder(),
      PeopleCandidateBuilder(),
      PlacesCandidateBuilder(),
      AestheticsCandidateBuilder(),
      CurationCandidateBuilder(),
      NarrativeCandidateBuilder(),
    ];
