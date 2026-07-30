import "package:collection/collection.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/services/collections_service.dart";

typedef FindUploadedFiles =
    Future<List<EnteFile>> Function(
      String hash,
      FileType fileType,
      int ownerID,
    );
typedef DeleteGeneratedFile = Future<void> Function(int generatedID);
typedef UpdateUploadedFileLocalID =
    Future<void> Function(int uploadedFileID, String localID);
typedef LinkExistingUpload =
    Future<EnteFile> Function(
      int collectionID, {
      required EnteFile localFileToUpload,
      required EnteFile existingUploadedFile,
    });
typedef EmitLocalPhotosUpdated = void Function(LocalPhotosUpdatedEvent event);

/// Resolves a pending upload to an already-uploaded file with the same hash.
///
/// Resolution priority and side effects intentionally match the legacy upload
/// flow: same local file in the target collection, missing local ID, same local
/// file in another collection, then no mapping.
class ExistingUploadResolver {
  ExistingUploadResolver({
    required FindUploadedFiles findUploadedFiles,
    required DeleteGeneratedFile deleteGeneratedFile,
    required UpdateUploadedFileLocalID updateUploadedFileLocalID,
    required LinkExistingUpload linkExistingUpload,
    required EmitLocalPhotosUpdated emitLocalPhotosUpdated,
  }) : _findUploadedFiles = findUploadedFiles,
       _deleteGeneratedFile = deleteGeneratedFile,
       _updateUploadedFileLocalID = updateUploadedFileLocalID,
       _linkExistingUpload = linkExistingUpload,
       _emitLocalPhotosUpdated = emitLocalPhotosUpdated;

  factory ExistingUploadResolver.forApp() => ExistingUploadResolver(
    findUploadedFiles: (hash, fileType, ownerID) =>
        FilesDB.instance.getUploadedFilesWithHash(hash, fileType, ownerID),
    deleteGeneratedFile: (generatedID) =>
        FilesDB.instance.deleteByGeneratedID(generatedID),
    updateUploadedFileLocalID: (uploadedFileID, localID) =>
        FilesDB.instance.updateLocalIDForUploaded(uploadedFileID, localID),
    linkExistingUpload:
        (
          collectionID, {
          required localFileToUpload,
          required existingUploadedFile,
        }) => CollectionsService.instance
            .linkLocalFileToExistingUploadedFileInAnotherCollection(
              collectionID,
              localFileToUpload: localFileToUpload,
              existingUploadedFile: existingUploadedFile,
            ),
    emitLocalPhotosUpdated: (event) => Bus.instance.fire(event),
  );

  final _logger = Logger("ExistingUploadResolver");
  final FindUploadedFiles _findUploadedFiles;
  final DeleteGeneratedFile _deleteGeneratedFile;
  final UpdateUploadedFileLocalID _updateUploadedFileLocalID;
  final LinkExistingUpload _linkExistingUpload;
  final EmitLocalPhotosUpdated _emitLocalPhotosUpdated;

  /// Returns the mapped file, or `null` when the caller should upload it.
  Future<EnteFile?> resolve({
    required String fileHash,
    required EnteFile fileToUpload,
    required int targetCollectionID,
    required int? ownerID,
  }) async {
    if (fileToUpload.uploadedFileID != null) {
      // This should never happen. Avoid mapping an already-uploaded row because
      // the branches below can delete or relink the pending local entry.
      _logger.severe("Critical: file is already uploaded, skipped mapping");
      return null;
    }
    if (ownerID == null) {
      return null;
    }

    final isSandboxFile = fileToUpload.isSharedMediaToAppSandbox;
    final existingUploadedFiles = await _findUploadedFiles(
      fileHash,
      fileToUpload.fileType,
      ownerID,
    );
    if (existingUploadedFiles.isEmpty) {
      return null;
    }

    // Case a: the same local file is already in the target collection.
    final sameLocalSameCollection = existingUploadedFiles.firstWhereOrNull(
      (file) =>
          file.collectionID == targetCollectionID &&
          (file.localID == fileToUpload.localID || isSandboxFile),
    );
    if (sameLocalSameCollection != null) {
      _logger.info(
        "sameLocalSameCollection: toUpload ${fileToUpload.tag} "
        "existing: ${sameLocalSameCollection.tag} $isSandboxFile",
      );
      if (fileToUpload.generatedID != null) {
        await _deleteGeneratedFile(fileToUpload.generatedID!);
      }
      _emitDeletedEvent(fileToUpload, "sameLocalSameCollection");
      return sameLocalSameCollection;
    }

    // Case b: reuse an uploaded file whose local ID is not known yet.
    final fileMissingLocal = existingUploadedFiles.firstWhereOrNull(
      (file) => file.localID == null,
    );
    if (fileMissingLocal != null) {
      _logger.info(
        "fileMissingLocal: \n toUpload ${fileToUpload.tag} "
        "\n existing: ${fileMissingLocal.tag}",
      );
      await _updateUploadedFileLocalID(
        fileMissingLocal.uploadedFileID!,
        fileToUpload.localID!,
      );
      if (fileToUpload.generatedID != null) {
        await _deleteGeneratedFile(fileToUpload.generatedID!);
      }
      _emitDeletedEvent(fileToUpload, "fileMissingLocal");
      fileMissingLocal.localID = fileToUpload.localID;
      return fileMissingLocal;
    }

    // Case c: link the same local file from another collection.
    final fileInDifferentCollection = existingUploadedFiles.firstWhereOrNull(
      (file) =>
          file.collectionID != targetCollectionID &&
          (file.localID == fileToUpload.localID || isSandboxFile),
    );
    if (fileInDifferentCollection != null) {
      _logger.info(
        "fileExistsButDifferentCollection: toUpload ${fileToUpload.tag} "
        "existing: ${fileInDifferentCollection.tag} $isSandboxFile",
      );
      return _linkExistingUpload(
        targetCollectionID,
        localFileToUpload: fileToUpload,
        existingUploadedFile: fileInDifferentCollection,
      );
    }

    // Case d: the hash belongs to a different local file, so upload this one.
    final matchLocalIDs = existingUploadedFiles
        .where((file) => file.localID != null)
        .map((file) => file.localID!)
        .toSet();
    _logger.info(
      "Found hashMatch but probably with diff localIDs $matchLocalIDs",
    );
    return null;
  }

  void _emitDeletedEvent(EnteFile file, String source) {
    _emitLocalPhotosUpdated(
      LocalPhotosUpdatedEvent(
        [file],
        type: EventType.deletedFromEverywhere,
        source: source,
      ),
    );
  }
}
