import "package:photo_manager/photo_manager.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/device_picker/device_media_library.dart";

AssetEntity media(String id) => AssetEntity(
  id: id,
  typeInt: 1,
  width: 1200,
  height: 800,
  title: '$id.jpg',
  createDateSecond: 1700000000,
);

class FakeDeviceLibrary implements DeviceMediaLibrary {
  PermissionState access = PermissionState.authorized;
  final folders = [
    AssetPathEntity(id: 'recent', name: 'Recent', isAll: true),
    AssetPathEntity(id: 'camera', name: 'Camera'),
  ];
  List<AssetEntity> items = List.generate(3, (index) => media('$index'));
  final unavailable = <String>{};
  final knownFiles = <String, EnteFile>{};
  final fileLookupBatches = <List<String>>[];
  Object? fileLookupError;
  Future<List<AssetEntity>> Function(AssetPathEntity, int, int)? readOverride;
  Future<AssetEntity?> Function(String)? resolveOverride;

  @override
  Future<PermissionState> permission({required bool request}) async => access;
  @override
  Future<List<AssetPathEntity>> albums() async => folders;
  @override
  Future<List<AssetEntity>> read(
    AssetPathEntity album, {
    required int start,
    required int end,
  }) async => readOverride != null
      ? readOverride!(album, start, end)
      : items.skip(start).take(end - start).toList();
  @override
  Future<Map<String, EnteFile>> files(List<String> localIDs) async {
    if (fileLookupError != null) throw fileLookupError!;
    fileLookupBatches.add(localIDs);
    return {
      for (final id in localIDs)
        if (knownFiles.containsKey(id)) id: knownFiles[id]!,
    };
  }

  @override
  Future<int> count(AssetPathEntity album) async => items.length;
  @override
  Future<AssetEntity?> resolve(String id) async => resolveOverride != null
      ? resolveOverride!(id)
      : unavailable.contains(id)
      ? null
      : items.where((item) => item.id == id).firstOrNull;
}
