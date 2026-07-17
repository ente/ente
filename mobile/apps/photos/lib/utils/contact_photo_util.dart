import "dart:typed_data";

import "package:photos/db/files_db.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/ml/face/face.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/module/download/thumbnail.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/services/search_service.dart";
import "package:photos/utils/face/face_thumbnail_cache.dart";

Future<Uint8List?> buildContactPhotoAttachmentBytesFromFace({
  required EnteFile file,
  required Face face,
}) async {
  final crops = await getCachedFaceCrops(
    file,
    [face],
    useFullFile: true,
    useTempCache: false,
  );
  final croppedBytes = crops?[face.faceID];
  if (croppedBytes == null) {
    return null;
  }
  return compressThumbnailToSizeLimit(croppedBytes);
}

Future<Uint8List?> buildContactPhotoAttachmentBytesFromPerson(
  PersonEntity person,
) async {
  final hiddenFileIds = await SearchService.instance.getHiddenFiles().then(
    (files) => files.map((file) => file.uploadedFileID).toSet(),
  );
  final faceIds = await MLDataDB.instance.getFaceIDsForPersonOrderedByScore(
    person.remoteID,
  );
  EnteFile? sourceFile;
  String? faceId = person.data.avatarFaceID;

  if (faceId != null) {
    final fileId = getFileIdFromFaceId<int>(faceId);
    if (!hiddenFileIds.contains(fileId)) {
      sourceFile = await FilesDB.instance.getAnyUploadedFile(fileId);
    }
  }

  if (sourceFile == null) {
    for (final candidateFaceId in faceIds) {
      final fileId = getFileIdFromFaceId<int>(candidateFaceId);
      if (hiddenFileIds.contains(fileId)) {
        continue;
      }
      sourceFile = await FilesDB.instance.getAnyUploadedFile(fileId);
      if (sourceFile != null) {
        faceId = candidateFaceId;
        break;
      }
    }
  }

  if (sourceFile == null || sourceFile.uploadedFileID == null) {
    return null;
  }

  final face = await MLDataDB.instance.getCoverFaceForPerson(
    recentFileID: sourceFile.uploadedFileID!,
    avatarFaceId: faceId,
    personID: person.remoteID,
  );
  if (face == null) {
    return null;
  }

  return buildContactPhotoAttachmentBytesFromFace(file: sourceFile, face: face);
}
