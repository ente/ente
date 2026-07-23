import 'package:logging/logging.dart';
import 'package:photos/gateways/files/files_gateway.dart';
import 'package:photos/models/duplicate_files.dart';
import "package:photos/models/file/extensions/file_props.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/models/file/file_type.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/files_service.dart";
import "package:photos/services/search_service.dart";

class DeduplicationService {
  final _logger = Logger("DeduplicationService");

  FilesGateway get _gateway => filesGateway;

  DeduplicationService._privateConstructor();

  static final DeduplicationService instance =
      DeduplicationService._privateConstructor();

  Future<List<DuplicateFiles>> getDuplicateFiles() async {
    try {
      final List<DuplicateFiles> result = await _getDuplicateFiles();
      return result;
    } catch (e, s) {
      _logger.severe("failed to get dedupeFile", e, s);
      rethrow;
    }
  }

  // Returns a list of DuplicateFiles, where each DuplicateFiles object contains
  // a list of files that have the same hash
  Future<List<DuplicateFiles>> _getDuplicateFiles() async {
    Map<int, int> uploadIDToSize = {};
    final bool hasFileSizes = await FilesService.instance.hasMigratedSizes();
    if (!hasFileSizes) {
      final DuplicateFilesResponse dupes = await _fetchDuplicateFileIDs();
      uploadIDToSize = dupes.toUploadIDToSize();
    }
    final Set<int> allowedCollectionIDs = CollectionsService.instance
        .nonHiddenOwnedCollections();

    final List<EnteFile> allFiles = await SearchService.instance
        .getAllFilesForSearch();
    final List<EnteFile> filteredFiles = [];
    for (final file in allFiles) {
      if (!file.isUploaded ||
          (file.hash ?? '').isEmpty ||
          !file.isOwner ||
          (!allowedCollectionIDs.contains(file.collectionID!))) {
        continue;
      }
      if ((file.fileSize ?? 0) <= 0) {
        file.fileSize = uploadIDToSize[file.uploadedFileID!] ?? 0;
      }
      if ((file.fileSize ?? 0) <= 0) {
        continue;
      }
      filteredFiles.add(file);
    }

    final Map<String, List<EnteFile>> sizeHashToFilesMap = {};
    final Map<String, Set<int>> sizeHashToCollectionsSet = {};
    final Map<String, List<EnteFile>> livePhotoHashToFilesMap = {};
    final Map<String, Set<int>> livePhotoHashToCollectionsSet = {};
    final Set<int> processedFileIds = <int>{};
    for (final file in filteredFiles) {
      // Note: For live photos, the zipped file size could be different if
      // the files were uploaded from different devices. So, we dedupe live
      // photos based on hash only.
      if (file.fileType == FileType.livePhoto) {
        final key = '${file.hash}';
        if (!livePhotoHashToFilesMap.containsKey(key)) {
          livePhotoHashToFilesMap[key] = <EnteFile>[];
          livePhotoHashToCollectionsSet[key] = <int>{};
        }
        livePhotoHashToCollectionsSet[key]!.add(file.collectionID!);
        if (!processedFileIds.contains(file.uploadedFileID)) {
          livePhotoHashToFilesMap[key]!.add(file);
          processedFileIds.add(file.uploadedFileID!);
        }
      } else {
        final key = '${file.fileSize}-${file.hash}';
        if (!sizeHashToFilesMap.containsKey(key)) {
          sizeHashToFilesMap[key] = <EnteFile>[];
          sizeHashToCollectionsSet[key] = <int>{};
        }
        sizeHashToCollectionsSet[key]!.add(file.collectionID!);
        if (!processedFileIds.contains(file.uploadedFileID)) {
          sizeHashToFilesMap[key]!.add(file);
          processedFileIds.add(file.uploadedFileID!);
        }
      }
    }
    final List<DuplicateFiles> dupesByHash = [];
    for (final key in sizeHashToFilesMap.keys) {
      final List<EnteFile> files = sizeHashToFilesMap[key]!;
      final Set<int> collectionIds = sizeHashToCollectionsSet[key]!;
      if (files.length > 1) {
        final size = files[0].fileSize!;
        dupesByHash.add(DuplicateFiles(files, size, collectionIds));
      }
    }
    for (final key in livePhotoHashToFilesMap.keys) {
      final List<EnteFile> files = livePhotoHashToFilesMap[key]!;
      final Set<int> collectionIds = livePhotoHashToCollectionsSet[key]!;
      if (files.length > 1 && (files.first.fileSize ?? 0) > 0) {
        dupesByHash.add(
          DuplicateFiles(files, files.first.fileSize!, collectionIds),
        );
      }
    }
    return dupesByHash;
  }

  Future<DuplicateFilesResponse> _fetchDuplicateFileIDs() async {
    return await _gateway.getDuplicates();
  }
}
