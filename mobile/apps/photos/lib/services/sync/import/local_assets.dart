import 'dart:io';
import 'dart:math';

import 'package:computer/computer.dart';
import 'package:logging/logging.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photos/core/errors.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/events/local_import_progress.dart';
import 'package:photos/models/file/file.dart';
import "package:photos/module/metadata/local_file.dart";
import "package:photos/services/sync/import/model.dart";
import 'package:tuple/tuple.dart';

final _logger = Logger("FileSyncUtil");
const ignoreSizeConstraint = SizeConstraint(ignoreSize: true);
const assetFetchPageSize = 2000;

Future<Tuple2<List<LocalPathAsset>, List<EnteFile>>> getLocalPathAssetsAndFiles(
  int fromTime,
  int toTime,
) async {
  final pathEntities = await _getGalleryList(
    updateFromTime: fromTime,
    updateToTime: toTime,
  );
  final List<LocalPathAsset> localPathAssets = [];

  // alreadySeenLocalIDs is used to track and ignore file with particular
  // localID if it's already present in another album. This only impacts iOS
  // devices where a file can belong to multiple
  final Set<String> alreadySeenLocalIDs = {};
  final List<EnteFile> uniqueFiles = [];
  for (AssetPathEntity pathEntity in pathEntities) {
    final List<AssetEntity> assetsInPath = await _getAllAssetLists(pathEntity);
    late Tuple2<Set<String>, List<EnteFile>> result;
    if (assetsInPath.isEmpty) {
      result = const Tuple2({}, []);
    } else {
      try {
        result = await Computer.shared().compute(
          _getLocalIDsAndFilesFromAssets,
          param: <String, dynamic>{
            "pathEntity": pathEntity,
            "fromTime": fromTime,
            "alreadySeenLocalIDs": alreadySeenLocalIDs,
            "assetList": assetsInPath,
          },
          taskName:
              "getLocalPathAssetsAndFiles-${pathEntity.name}-count-${assetsInPath.length}",
        );
      } catch (e) {
        _logger.severe("_getLocalIDsAndFilesFromAssets failed", e);
        _logger.info("Failed for pathEntity: ${pathEntity.name}");
        rethrow;
      }

      alreadySeenLocalIDs.addAll(result.item1);
      uniqueFiles.addAll(result.item2);
    }
    localPathAssets.add(
      LocalPathAsset(
        localIDs: result.item1,
        pathName: pathEntity.name,
        pathID: pathEntity.id,
      ),
    );
  }
  return Tuple2(localPathAssets, uniqueFiles);
}

// getDeviceFolderWithCountAndLatestFile returns a tuple of AssetPathEntity and
// latest file's localID in the assetPath, along with modifiedPath time and
// total count of assets in a Asset Path.
// We use this result to update the latest thumbnail for deviceFolder and
// identify (in future) which AssetPath needs to be re-synced again.
Future<List<Tuple2<AssetPathEntity, String>>>
getDeviceFolderWithCountAndCoverID() async {
  final List<Tuple2<AssetPathEntity, String>> result = [];
  final pathEntities = await _getGalleryList(
    needsTitle: false,
    containsModifiedPath: true,
    orderOption: const OrderOption(
      type: OrderOptionType.createDate,
      asc: false,
    ),
  );
  for (AssetPathEntity pathEntity in pathEntities) {
    final latestEntity = await pathEntity.getAssetListPaged(page: 0, size: 1);
    final String localCoverID = latestEntity.isEmpty
        ? ''
        : latestEntity.first.id;
    result.add(Tuple2(pathEntity, localCoverID));
  }
  return result;
}

Future<List<LocalPathAsset>> getAllLocalAssets({bool? needsTitle}) async {
  final filterOptionGroup = FilterOptionGroup();
  final FilterOption imageFilterOption = needsTitle == null
      ? const FilterOption(sizeConstraint: ignoreSizeConstraint)
      : FilterOption(
          needTitle: needsTitle,
          sizeConstraint: ignoreSizeConstraint,
        );
  final FilterOption videoFilterOption = needsTitle == null
      ? const FilterOption(sizeConstraint: ignoreSizeConstraint)
      : FilterOption(
          needTitle: needsTitle,
          sizeConstraint: ignoreSizeConstraint,
        );
  filterOptionGroup.setOption(AssetType.image, imageFilterOption);
  filterOptionGroup.setOption(AssetType.video, videoFilterOption);
  filterOptionGroup.createTimeCond = DateTimeCond.def().copyWith(ignore: true);
  final assetPaths = await PhotoManager.getAssetPathList(
    hasAll: !Platform.isAndroid,
    type: RequestType.common,
    filterOption: filterOptionGroup,
  );
  final List<LocalPathAsset> localPathAssets = [];
  for (final assetPath in assetPaths) {
    final Set<String> localIDs = <String>{};
    for (final asset in await _getAllAssetLists(assetPath)) {
      localIDs.add(asset.id);
    }
    localPathAssets.add(
      LocalPathAsset(
        localIDs: localIDs,
        pathName: assetPath.name,
        pathID: assetPath.id,
      ),
    );
  }
  return localPathAssets;
}

/// returns a list of AssetPathEntity with relevant filter operations.
/// [needTitle] impacts the performance for fetching the actual [AssetEntity]
/// in iOS. Same is true for [containsModifiedPath]
Future<List<AssetPathEntity>> _getGalleryList({
  final int? updateFromTime,
  final int? updateToTime,
  final bool containsModifiedPath = false,
  // in iOS fetching the AssetEntity title impacts performance
  final bool needsTitle = true,
  final OrderOption? orderOption,
}) async {
  final filterOptionGroup = FilterOptionGroup();
  filterOptionGroup.setOption(
    AssetType.image,
    FilterOption(needTitle: needsTitle, sizeConstraint: ignoreSizeConstraint),
  );
  filterOptionGroup.setOption(
    AssetType.video,
    FilterOption(needTitle: needsTitle, sizeConstraint: ignoreSizeConstraint),
  );

  if (orderOption != null) {
    filterOptionGroup.addOrderOption(orderOption);
  }

  if (updateFromTime != null && updateToTime != null) {
    filterOptionGroup.updateTimeCond = DateTimeCond(
      min: DateTime.fromMillisecondsSinceEpoch(updateFromTime ~/ 1000),
      max: DateTime.fromMillisecondsSinceEpoch(updateToTime ~/ 1000),
    );
  }
  filterOptionGroup.containsPathModified = containsModifiedPath;
  final galleryList = await PhotoManager.getAssetPathList(
    hasAll: !Platform.isAndroid,
    type: RequestType.common,
    filterOption: filterOptionGroup,
  );
  galleryList.sort((s1, s2) {
    if (s1.isAll) {
      return 1;
    }
    return 0;
  });

  return galleryList;
}

Future<List<AssetEntity>> _getAllAssetLists(AssetPathEntity pathEntity) async {
  final List<AssetEntity> result = [];
  int currentPage = 0;
  List<AssetEntity> currentPageResult = [];
  do {
    currentPageResult = await pathEntity.getAssetListPaged(
      page: currentPage,
      size: assetFetchPageSize,
    );
    Bus.instance.fire(
      LocalImportProgressEvent(
        pathEntity.name,
        currentPage * assetFetchPageSize + currentPageResult.length,
      ),
    );
    result.addAll(currentPageResult);
    currentPage = currentPage + 1;
  } while (currentPageResult.length >= assetFetchPageSize);
  return result;
}

/// Safely extracts millisecondsSinceEpoch from DateTime, throwing InvalidDateTimeError if invalid
int _safeGetMilliseconds(
  DateTime dateTime,
  String assetId,
  String? assetTitle,
  String label,
) {
  try {
    return dateTime.millisecondsSinceEpoch;
  } on RangeError catch (e) {
    throw InvalidDateTimeError(
      assetId: assetId,
      assetTitle: assetTitle,
      field: label,
      originalError: e.message ?? e.toString(),
    );
  }
}

// Runs in a worker isolate because a device folder can contain thousands of
// assets and this loop constructs metadata for the full folder. Re-benchmark
// large imports before moving this work onto the UI isolate.
Tuple2<Set<String>, List<EnteFile>> _getLocalIDsAndFilesFromAssets(
  Map<String, dynamic> args,
) {
  final pathEntity = args["pathEntity"] as AssetPathEntity;
  final assetList = args["assetList"];
  final fromTime = args["fromTime"];
  final alreadySeenLocalIDs = args["alreadySeenLocalIDs"] as Set<String>;
  final List<EnteFile> files = [];
  final Set<String> localIDs = {};
  for (AssetEntity entity in assetList) {
    localIDs.add(entity.id);
    final createMs = _safeGetMilliseconds(
      entity.createDateTime,
      entity.id,
      entity.title,
      'createDateTime',
    );
    final modifiedMs = _safeGetMilliseconds(
      entity.modifiedDateTime,
      entity.id,
      entity.title,
      'modifiedDateTime',
    );
    final bool assetCreatedOrUpdatedAfterGivenTime =
        max(createMs, modifiedMs) >= (fromTime ~/ 1000);
    if (!alreadySeenLocalIDs.contains(entity.id) &&
        assetCreatedOrUpdatedAfterGivenTime) {
      final file = fileFromAsset(pathEntity.name, entity);
      files.add(file);
    }
  }
  return Tuple2(localIDs, files);
}
