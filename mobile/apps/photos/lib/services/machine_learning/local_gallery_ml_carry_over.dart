import "package:collection/collection.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:logging/logging.dart";
import "package:photos/db/ml/clip_vector_db.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/db/offline_files_db.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/ml/clip.dart";
import "package:photos/models/ml/face/face.dart";
import "package:photos/models/ml/ml_versions.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/filedata/model/file_data.dart";
import "package:photos/services/machine_learning/ml_run_control.dart";
import "package:photos/utils/ml_util.dart";

final _logger = Logger("LocalGalleryMLCarryOver");

typedef _LocalGalleryResults = ({
  Map<int, List<Face>> faces,
  Map<int, ClipEmbedding> clips,
});

Future<List<FileMLInstruction>> getLocalGalleryCarryOverCandidates(
  List<FileMLInstruction> instructions,
) async {
  try {
    final localIntIDs = await _localIntIDsForCarryOver(instructions);
    if (localIntIDs.isEmpty) return [];
    final carriable = instructions
        .where(
          (instruction) =>
              _canCarryOver(instruction) &&
              localIntIDs.containsKey(instruction.file.localID),
        )
        .toList();
    final candidates = <FileMLInstruction>[];
    for (final chunk in carriable.chunks(embeddingFetchLimit)) {
      final results = await _loadLocalGalleryResults(
        chunk
            .map((instruction) => localIntIDs[instruction.file.localID]!)
            .toSet()
            .toList(),
      );
      candidates.addAll(
        chunk.where((instruction) {
          final key = localIntIDs[instruction.file.localID]!;
          final clip = results.clips[key];
          return _completesFileData(
            instruction,
            hasFaces: results.faces[key]?.any(_isUsableFace) ?? false,
            hasClip: clip != null && _isUsableClip(clip),
          );
        }),
      );
    }
    return candidates;
  } catch (e, s) {
    _logger.warning("Could not find local gallery ML carry-over files", e, s);
    return [];
  }
}

Future<List<FileMLInstruction>> carryOverLocalGalleryMLData(
  List<FileMLInstruction> instructions, {
  required String client,
  MlRunControl? control,
}) async {
  Set<FileMLInstruction> failedUploads = {};
  try {
    failedUploads = await _carryOver(
      instructions,
      client: client,
      control: control,
    );
  } catch (e, s) {
    _logger.warning("Could not carry over local gallery ML data", e, s);
  }
  return instructions
      .where(
        (instruction) =>
            instruction.pendingML && !failedUploads.contains(instruction),
      )
      .toList();
}

Future<Set<FileMLInstruction>> _carryOver(
  List<FileMLInstruction> instructions, {
  required String client,
  MlRunControl? control,
}) async {
  final carriable = instructions
      .where((instruction) => instruction.remoteMLStateKnown)
      .toList();
  final localIntIDs = await _localIntIDsForCarryOver(carriable);
  if (localIntIDs.isEmpty) return {};
  final results = await _loadLocalGalleryResults(
    localIntIDs.values.toSet().toList(),
  );

  final carriedFaces = <Face>[];
  final carriedClips = <ClipEmbedding>[];
  final failedUploads = <FileMLInstruction>{};
  int carriedFileCount = 0;
  for (final instruction in carriable) {
    if (control?.stopRequested ?? false) break;
    final key = localIntIDs[instruction.file.localID];
    if (key == null || !_canCarryOver(instruction)) continue;
    final fileID = instruction.file.uploadedFileID!;
    final faces = instruction.shouldRunFaces
        ? _facesForFile(results.faces[key], fileID)
        : null;
    final clip = instruction.shouldRunClip
        ? _clipForFile(results.clips[key], fileID)
        : null;
    if (!_completesFileData(
      instruction,
      hasFaces: faces != null,
      hasClip: clip != null,
    )) {
      continue;
    }

    final data = FileDataEntity(fileID, {
      ...?instruction.existingRemoteFileML?.remoteRawData,
    }, DataType.mlData);
    if (faces != null) {
      final fileInfo = faces.first.fileInfo;
      data.putFace(
        RemoteFaceEmbedding(
          faces,
          faceMlVersion,
          client: client,
          height: fileInfo?.imageHeight ?? 0,
          width: fileInfo?.imageWidth ?? 0,
        ),
      );
    }
    if (clip != null) {
      data.putClip(
        RemoteClipEmbedding(
          clip.embedding,
          version: clipMlVersion,
          client: client,
        ),
      );
    }
    try {
      await fileDataService.putFileData(instruction.file, data);
    } catch (e, s) {
      _logger.warning("Could not upload carried-over ML for $fileID", e, s);
      failedUploads.add(instruction);
      continue;
    }
    if (faces != null) {
      carriedFaces.addAll(faces);
      instruction.shouldRunFaces = false;
    }
    if (clip != null) {
      carriedClips.add(clip);
      instruction.shouldRunClip = false;
    }
    carriedFileCount++;
  }

  if (carriedFileCount > 0) {
    await MLDataDB.instance.bulkInsertFaces(carriedFaces);
    await MLDataDB.instance.putClip(carriedClips);
    _logger.info(
      "Carried over local gallery ML results for $carriedFileCount files",
    );
  }
  return failedUploads;
}

bool _canCarryOver(FileMLInstruction instruction) =>
    instruction.file.isOwner &&
    (instruction.file.localID ?? '').isNotEmpty &&
    (instruction.shouldRunFaces || instruction.shouldRunClip);

Future<Map<String, int>> _localIntIDsForCarryOver(
  List<FileMLInstruction> instructions,
) async {
  final localIDs = {
    for (final instruction in instructions)
      if (_canCarryOver(instruction)) instruction.file.localID!,
  };
  if (localIDs.isEmpty || !await MLDataDB.hasLocalGalleryDatabase()) {
    return {};
  }
  return OfflineFilesDB.instance.getLocalIntIdsForLocalIds(localIDs);
}

Future<_LocalGalleryResults> _loadLocalGalleryResults(List<int> keys) async {
  final localGalleryDB = MLDataDB.localGalleryInstance;
  return (
    faces: groupBy(
      await localGalleryDB.getFacesForFileIDs(keys),
      (Face face) => face.fileID,
    ),
    clips: {
      for (final clip in await localGalleryDB.getClipEmbeddingsForFileIDs(keys))
        clip.fileID: clip,
    },
  );
}

bool _completesFileData(
  FileMLInstruction instruction, {
  required bool hasFaces,
  required bool hasClip,
}) {
  final remote = instruction.existingRemoteFileML;
  final facesCovered = instruction.shouldRunFaces
      ? hasFaces
      : remote?.hasFace ?? false;
  final clipCovered = instruction.shouldRunClip
      ? hasClip
      : remote?.hasClip ?? false;
  return facesCovered && clipCovered;
}

bool _isUsableFace(Face face) => face.score >= 0;

bool _isUsableClip(ClipEmbedding clip) =>
    clip.embedding.length == ClipVectorDB.embeddingDimensions;

List<Face>? _facesForFile(List<Face>? localGalleryFaces, int fileID) {
  final faces = localGalleryFaces?.where(_isUsableFace).toList();
  if (faces == null || faces.isEmpty) return null;
  return faces
      .map(
        (face) => Face(
          "$fileID${face.faceID.substring(face.faceID.indexOf('_'))}",
          fileID,
          face.embedding,
          face.score,
          face.detection,
          face.blur,
          fileInfo: face.fileInfo,
        ),
      )
      .toList();
}

ClipEmbedding? _clipForFile(ClipEmbedding? localGalleryClip, int fileID) {
  if (localGalleryClip == null || !_isUsableClip(localGalleryClip)) {
    return null;
  }
  return ClipEmbedding(
    fileID: fileID,
    embedding: localGalleryClip.embedding,
    version: clipMlVersion,
  );
}
