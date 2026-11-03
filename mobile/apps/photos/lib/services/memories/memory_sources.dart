import "package:photos/db/files_db.dart";
import "package:photos/db/memories_db.dart";
import "package:photos/db/offline_files_db.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/metadata/common_keys.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/search_service.dart";

MemoriesDB get memoriesDB =>
    isLocalGalleryMode ? MemoriesDB.localGalleryInstance : MemoriesDB.instance;

Future<Map<int, EnteFile>> getFilesAndMapForMemories({
  bool useGeneratedIds = false,
  bool requireLocalId = false,
  bool useLocalIntIds = false,
}) async {
  final allFilesFromSearchService = await SearchService.instance
      .getAllFilesForSearch();
  final archivedOrHiddenCollectionIDs = CollectionsService.instance
      .archivedOrHiddenCollectionIds();
  final excludedUploadFileIDs = <int>{};
  if (archivedOrHiddenCollectionIDs.isNotEmpty) {
    final filesInArchivedCollections = await FilesDB.instance
        .getAllFilesFromCollections(archivedOrHiddenCollectionIDs);
    for (final archivedFile in filesInArchivedCollections) {
      final archivedUploadID = archivedFile.uploadedFileID;
      if (archivedUploadID != null && archivedUploadID != -1) {
        excludedUploadFileIDs.add(archivedUploadID);
      }
    }
  }
  final candidateFiles = <EnteFile>[];
  for (final file in allFilesFromSearchService) {
    final localId = file.localID;
    final hasLocalId = localId != null && localId.isNotEmpty;
    if (requireLocalId && !hasLocalId) {
      continue;
    }
    final hasId = useLocalIntIds
        ? hasLocalId
        : useGeneratedIds
        ? file.generatedID != null &&
              (file.uploadedFileID != null || hasLocalId)
        : file.uploadedFileID != null;
    if (hasId && file.creationTime != null) {
      if (excludedUploadFileIDs.contains(file.uploadedFileID)) {
        continue;
      }
      if (file.magicMetadata.visibility == archiveVisibility ||
          file.magicMetadata.visibility == hiddenVisibility) {
        continue;
      }
      final collectionID = file.collectionID;
      if (collectionID != null &&
          archivedOrHiddenCollectionIDs.contains(collectionID)) {
        continue;
      }
      candidateFiles.add(file);
    }
  }
  final Map<String, int> localIdToIntId = useLocalIntIds
      ? await OfflineFilesDB.instance.ensureLocalIntIds(
          candidateFiles
              .map((file) => file.localID)
              .whereType<String>()
              .where((id) => id.isNotEmpty),
        )
      : <String, int>{};
  final allFileIdsToFile = <int, EnteFile>{};
  for (final file in candidateFiles) {
    final localIntId = useLocalIntIds ? localIdToIntId[file.localID] : null;
    final mappedFile = localIntId != null
        ? file.copyWith(generatedID: localIntId)
        : file;
    final key = useLocalIntIds
        ? localIntId
        : useGeneratedIds
        ? mappedFile.generatedID
        : mappedFile.uploadedFileID;
    if (key != null) {
      allFileIdsToFile[key] = mappedFile;
    }
  }
  return allFileIdsToFile;
}

Future<Set<int>> getCollectionIDsToExclude() async {
  if (isLocalGalleryMode) {
    return <int>{};
  }
  final collections = CollectionsService.instance.getCollectionsForUI();

  const excludedNames = {
    'screenshot',
    'whatsapp',
    'telegram',
    'download',
    'facebook',
    'instagram',
    'messenger',
    'twitter',
    'reddit',
    'discord',
    'signal',
    'viber',
    'wechat',
    'line',
    'meme',
    'internet',
    'saved images',
    'document',
  };

  final excludedCollectionIDs = Set<int>.from(
    CollectionsService.instance.archivedOrHiddenCollectionIds(),
  );
  collectionLoop:
  for (final collection in collections) {
    final collectionName = collection.displayName.toLowerCase();
    for (final excludedName in excludedNames) {
      if (collectionName.contains(excludedName)) {
        excludedCollectionIDs.add(collection.id);
        continue collectionLoop;
      }
    }
  }

  return excludedCollectionIDs;
}
