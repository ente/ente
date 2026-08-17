import "package:computer/computer.dart";
import "package:logging/logging.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/models/file/file.dart";
import "package:photos/module/metadata/local_file.dart";
import "package:photos/services/sync/import/model.dart";

class LocalDiffResult {
  final List<LocalPathAsset>? localPathAssets;

  List<EnteFile>? uniqueLocalFiles;

  final Map<String, Set<String>>? newPathToLocalIDs;

  final Map<String, Set<String>>? deletePathToLocalIDs;

  LocalDiffResult({
    this.uniqueLocalFiles,
    this.localPathAssets,
    this.newPathToLocalIDs,
    this.deletePathToLocalIDs,
  });
}

Future<LocalDiffResult> getDiffFromExistingImport(
  List<LocalPathAsset> assets,
  Set<String> existingIDs,
  Map<String, Set<String>> pathToLocalIDs,
) async {
  final Map<String, dynamic> args = <String, dynamic>{};
  args['assets'] = assets;
  args['existingIDs'] = existingIDs;
  args['pathToLocalIDs'] = pathToLocalIDs;
  final LocalDiffResult diffResult = await Computer.shared().compute(
    _getLocalAssetsDiff,
    param: args,
    taskName: "getLocalAssetsDiff",
  );
  if (diffResult.localPathAssets != null) {
    diffResult.uniqueLocalFiles = await _convertLocalAssetsToUniqueFiles(
      diffResult.localPathAssets!,
    );
  }
  return diffResult;
}

Future<List<EnteFile>> _convertLocalAssetsToUniqueFiles(
  List<LocalPathAsset> assets,
) async {
  final Set<String> alreadySeenLocalIDs = <String>{};
  final List<EnteFile> files = [];
  for (LocalPathAsset localPathAsset in assets) {
    final String localPathName = localPathAsset.pathName;
    for (final String localID in localPathAsset.localIDs) {
      if (!alreadySeenLocalIDs.contains(localID)) {
        final assetEntity = await AssetEntity.fromId(localID);
        if (assetEntity == null) {
          Logger(
            "_convertLocalAssetsToUniqueFiles",
          ).warning('Failed to fetch asset with id $localID');
          continue;
        }
        files.add(fileFromAsset(localPathName, assetEntity));
        alreadySeenLocalIDs.add(localID);
      }
    }
  }
  return files;
}

LocalDiffResult _getLocalAssetsDiff(Map<String, dynamic> args) {
  final List<LocalPathAsset> onDeviceLocalPathAsset = args['assets'];
  final Set<String> existingIDs = args['existingIDs'];
  final Map<String, Set<String>> pathToLocalIDs = args['pathToLocalIDs'];
  final Map<String, Set<String>> newPathToLocalIDs = <String, Set<String>>{};
  final Map<String, Set<String>> removedPathToLocalIDs =
      <String, Set<String>>{};
  final List<LocalPathAsset> unsyncedAssets = [];

  for (final localPathAsset in onDeviceLocalPathAsset) {
    final String pathID = localPathAsset.pathID;
    final Set<String> candidateLocalIDsForRemoval =
        pathToLocalIDs[pathID] ?? <String>{};
    final Set<String> missingLocalIDsInPath = <String>{};
    for (final String localID in localPathAsset.localIDs) {
      if (candidateLocalIDsForRemoval.contains(localID)) {
        // Remove IDs still present; any IDs left afterward were removed from
        // the device folder.
        candidateLocalIDsForRemoval.remove(localID);
      } else {
        missingLocalIDsInPath.add(localID);
      }
    }
    if (candidateLocalIDsForRemoval.isNotEmpty) {
      removedPathToLocalIDs[pathID] = candidateLocalIDsForRemoval;
    }
    if (missingLocalIDsInPath.isNotEmpty) {
      newPathToLocalIDs[pathID] = missingLocalIDsInPath;
    }
    localPathAsset.localIDs.removeAll(existingIDs);
    if (localPathAsset.localIDs.isNotEmpty) {
      unsyncedAssets.add(localPathAsset);
    }
  }
  return LocalDiffResult(
    localPathAssets: unsyncedAssets,
    newPathToLocalIDs: newPathToLocalIDs,
    deletePathToLocalIDs: removedPathToLocalIDs,
  );
}
