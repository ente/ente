import "package:ml_linalg/vector.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/memories/clip_memory.dart";
import "package:photos/models/memories/memories_cache.dart";
import "package:photos/models/memories/people_memory.dart";
import "package:photos/models/ml/face/face_with_embedding.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/models/ml/vector.dart";
import "package:photos/services/location_service.dart";

class MemoriesComputationContext {
  final Map<int, EnteFile> allFileIdsToFile;
  final Set<int> collectionIDsToExclude;
  final bool isLocalGalleryMode;
  final bool mlEnabled;
  final DateTime now;
  final MemoriesCache oldCache;
  final bool debugSurfaceAll;
  final bool canUseUnnamedFallback;
  final Map<int, int> seenTimes;
  final List<PersonEntity> persons;
  final String? currentUserEmail;
  final List<City> cities;
  final Map<int, List<FaceWithoutEmbedding>> fileIdToFaces;
  final Map<String, int> clusterIdToFaceCount;
  final Map<String, Iterable<String>> clusterIdToFaceIDs;
  final Set<String> assignedClusterIDs;
  final List<EmbeddingVector> allImageEmbeddings;
  final Vector clipPositiveTextVector;
  final Map<PeopleActivity, Vector> clipPeopleActivityVectors;
  final Map<ClipMemoryType, Vector> clipMemoryTypeVectors;

  const MemoriesComputationContext({
    required this.allFileIdsToFile,
    required this.collectionIDsToExclude,
    required this.isLocalGalleryMode,
    required this.mlEnabled,
    required this.now,
    required this.oldCache,
    required this.debugSurfaceAll,
    required this.canUseUnnamedFallback,
    required this.seenTimes,
    required this.persons,
    required this.currentUserEmail,
    required this.cities,
    required this.fileIdToFaces,
    required this.clusterIdToFaceCount,
    required this.clusterIdToFaceIDs,
    required this.assignedClusterIDs,
    required this.allImageEmbeddings,
    required this.clipPositiveTextVector,
    required this.clipPeopleActivityVectors,
    required this.clipMemoryTypeVectors,
  });

  factory MemoriesComputationContext.fromIsolateArgs(
    Map<String, dynamic> args,
  ) {
    return MemoriesComputationContext(
      allFileIdsToFile: Map<int, EnteFile>.from(
        args["allFileIdsToFile"] as Map,
      ),
      collectionIDsToExclude: (args["collectionIDsToExclude"] as Set)
          .cast<int>(),
      isLocalGalleryMode: args["isLocalGalleryMode"] ?? false,
      mlEnabled: args["mlEnabled"] ?? false,
      now: args["now"] as DateTime,
      oldCache: args["oldCache"] as MemoriesCache,
      debugSurfaceAll: args["debugSurfaceAll"] ?? false,
      canUseUnnamedFallback: args["canUseUnnamedFallback"] ?? false,
      seenTimes: Map<int, int>.from(args["seenTimes"] as Map),
      persons: (args["persons"] as List).cast<PersonEntity>(),
      currentUserEmail: args["currentUserEmail"] as String?,
      cities: (args["cities"] as List).cast<City>(),
      fileIdToFaces: Map<int, List<FaceWithoutEmbedding>>.from(
        args["fileIdToFaces"] as Map,
      ),
      clusterIdToFaceCount: Map<String, int>.from(
        args["clusterIdToFaceCount"] as Map,
      ),
      clusterIdToFaceIDs: Map<String, Iterable<String>>.from(
        args["clusterIdToFaceIDs"] as Map,
      ),
      assignedClusterIDs: (args["assignedClusterIDs"] as Set).cast<String>(),
      allImageEmbeddings: (args["allImageEmbeddings"] as List)
          .cast<EmbeddingVector>(),
      clipPositiveTextVector: args["clipPositiveTextVector"] as Vector,
      clipPeopleActivityVectors: Map<PeopleActivity, Vector>.from(
        args["clipPeopleActivityVectors"] as Map,
      ),
      clipMemoryTypeVectors: Map<ClipMemoryType, Vector>.from(
        args["clipMemoryTypeVectors"] as Map,
      ),
    );
  }

  Map<String, dynamic> toIsolateArgs() {
    return <String, dynamic>{
      "allFileIdsToFile": allFileIdsToFile,
      "collectionIDsToExclude": collectionIDsToExclude,
      "isLocalGalleryMode": isLocalGalleryMode,
      "mlEnabled": mlEnabled,
      "now": now,
      "oldCache": oldCache,
      "debugSurfaceAll": debugSurfaceAll,
      "canUseUnnamedFallback": canUseUnnamedFallback,
      "seenTimes": seenTimes,
      "persons": persons,
      "currentUserEmail": currentUserEmail,
      "cities": cities,
      "fileIdToFaces": fileIdToFaces,
      "clusterIdToFaceCount": clusterIdToFaceCount,
      "clusterIdToFaceIDs": clusterIdToFaceIDs,
      "assignedClusterIDs": assignedClusterIDs,
      "allImageEmbeddings": allImageEmbeddings,
      "clipPositiveTextVector": clipPositiveTextVector,
      "clipPeopleActivityVectors": clipPeopleActivityVectors,
      "clipMemoryTypeVectors": clipMemoryTypeVectors,
    };
  }
}
