import "package:photo_manager/photo_manager.dart";
import "package:photos/db/files_db.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/module/metadata/local_file.dart";

EnteFile devicePickerFileFromAsset(
  String folder,
  AssetEntity asset,
  EnteFile indexed,
) {
  final file = fileFromAsset(folder, asset)..duration = asset.duration;
  file.creationTime = indexed.creationTime ?? file.creationTime;
  final metadata = indexed.pubMmdEncodedJson;
  if (metadata != null && metadata != '{}') {
    file.pubMmdEncodedJson = metadata;
    if (!indexed.hasDimensions) {
      applyDisplayDimensions(
        file,
        asset.orientatedWidth,
        asset.orientatedHeight,
      );
    }
  }
  return file;
}

abstract interface class DeviceMediaLibrary {
  Future<PermissionState> permission({required bool request});
  Future<List<AssetPathEntity>> albums();
  Future<List<AssetEntity>> read(
    AssetPathEntity album, {
    required int start,
    required int end,
  });
  Future<List<AssetEntity>> readFirstPage(AssetPathEntity album, int size);
  Future<AssetEntity?> resolve(String id);
  Future<Map<String, EnteFile>> files(List<String> localIDs);
  Future<int> count(AssetPathEntity album);
}

class PhotoManagerDeviceLibrary implements DeviceMediaLibrary {
  const PhotoManagerDeviceLibrary({this.requestType = RequestType.common});

  final RequestType requestType;

  @override
  Future<PermissionState> permission({required bool request}) {
    final option = PermissionRequestOption(
      androidPermission: AndroidPermission(
        type: requestType,
        mediaLocation: true,
      ),
    );
    return request
        ? PhotoManager.requestPermissionExtend(requestOption: option)
        : PhotoManager.getPermissionState(requestOption: option);
  }

  @override
  Future<List<AssetPathEntity>> albums() => PhotoManager.getAssetPathList(
    type: requestType,
    filterOption: FilterOptionGroup(
      imageOption: const FilterOption(
        sizeConstraint: SizeConstraint(ignoreSize: true),
      ),
      videoOption: const FilterOption(
        sizeConstraint: SizeConstraint(ignoreSize: true),
      ),
      createTimeCond: DateTimeCond.def().copyWith(ignore: true),
      orders: [const OrderOption(type: OrderOptionType.createDate)],
    ),
  );

  @override
  Future<List<AssetEntity>> read(
    AssetPathEntity album, {
    required int start,
    required int end,
  }) => album.getAssetListRange(start: start, end: end);

  @override
  Future<List<AssetEntity>> readFirstPage(AssetPathEntity album, int size) =>
      album.getAssetListPaged(page: 0, size: size);

  @override
  Future<Map<String, EnteFile>> files(List<String> localIDs) async {
    if (localIDs.isEmpty) return {};
    final files = await FilesDB.instance.getLocalFiles(localIDs);
    final byID = <String, EnteFile>{};
    for (final file in files.where((file) => file.isOwner)) {
      if (byID[file.localID]?.isUploaded != true) {
        byID[file.localID!] = file;
      }
    }
    return byID;
  }

  @override
  Future<int> count(AssetPathEntity album) => album.assetCountAsync;

  @override
  Future<AssetEntity?> resolve(String id) => AssetEntity.fromId(id);
}
