import "package:collection/collection.dart";
import "package:logging/logging.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/models/device_collection.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/search/device_album_search_result.dart";
import "package:photos/models/search/search_types.dart";
import "package:photos/module/metadata/local_file.dart";
import "package:photos/ui/device_picker/device_media_library.dart";
import "package:photos/ui/device_picker/device_picker_controller.dart";

Future<DeviceAlbumSearchResult?> deviceAlbumPickerResult(
  DeviceMediaLibrary library,
  AssetPathEntity album, {
  bool filenameMatches = false,
}) async {
  try {
    final (cover, count) = await (
      library.readFirstPage(album, 1),
      filenameMatches ? Future.value(0) : library.count(album),
    ).wait;
    final collection = DeviceCollection(
      album.id,
      album.name,
      count: count,
      thumbnail: cover.isEmpty ? null : fileFromAsset(album.name, cover.first),
    );
    if (filenameMatches) {
      return cover.isEmpty ? null : PickerFilenameResult(album, collection);
    }
    return DeviceAlbumSearchResult(collection);
  } catch (error, stack) {
    Logger(
      "DevicePicker",
    ).warning("Could not read device folder preview", error, stack);
    return filenameMatches
        ? null
        : DeviceAlbumSearchResult(DeviceCollection(album.id, album.name));
  }
}

class PickerFilenameResult extends DeviceAlbumSearchResult {
  PickerFilenameResult(this.album, super.deviceCollection);

  final AssetPathEntity album;

  @override
  ResultType type() => ResultType.file;
}

Future<List<DeviceAlbumSearchResult>> searchLocalPickerAlbums(
  DevicePickerController model,
  String query,
) async {
  final normalized = query.toLowerCase();
  final folders = model.albums.where(
    (album) => !album.isAll && album.name.toLowerCase().contains(normalized),
  );
  final searches = [
    for (final folder in folders.take(20))
      deviceAlbumPickerResult(model.library, folder),
  ];
  final recent = model.recentAlbum;
  if (recent != null && !query.contains('\u0000')) {
    const columns = CustomColumns.android;
    final types = [
      if (recent.type.containsImage()) 1,
      if (recent.type.containsVideo()) 3,
    ];
    final name = query.replaceAll("'", "''");
    final filenames = recent.copyWith(
      name: query,
      filterOption: CustomFilter.sql(
        where:
            "${columns.mediaType} IN (${types.join(',')}) AND "
            "instr(lower(_display_name), lower('$name')) > 0",
        orderBy: [OrderByItem.desc(columns.id)],
      ),
    );
    searches.add(
      deviceAlbumPickerResult(model.library, filenames, filenameMatches: true),
    );
  }
  final results = await Future.wait(searches);
  return results.nonNulls.toList();
}

Future<void> resolveLocalSearchFiles(
  DevicePickerController model,
  Iterable<EnteFile> files,
  Map<String, EnteFile?> eligible,
  bool Function() isCurrent,
) async {
  final indexed = {
    for (final file in files)
      if (file.localID case final id? when !eligible.containsKey(id)) id: file,
  };
  if (indexed.isEmpty) return;
  final access = model.permission;
  try {
    final assets = await accessiblePickerAssets(model, indexed.keys, isCurrent);
    if (!isCurrent()) return;
    for (final entry in indexed.entries) {
      final asset = assets[entry.key];
      eligible[entry.key] = asset == null
          ? null
          : devicePickerFileFromAsset('', asset, entry.value);
    }
  } catch (error, stack) {
    final permission = await model.library.permission(request: false);
    if (!permission.hasAccess || permission != access) rethrow;
    Logger("DevicePicker").warning("Could not read search media", error, stack);
  }
}

bool _matchesType(AssetEntity asset, RequestType requestType) =>
    (asset.type == AssetType.image && requestType.containsImage()) ||
    (asset.type == AssetType.video && requestType.containsVideo());

Future<Map<String, AssetEntity>> accessiblePickerAssets(
  DevicePickerController model,
  Iterable<String> ids,
  bool Function() isCurrent,
) async {
  final recent = model.recentAlbum;
  final matches = <String, AssetEntity>{};
  if (!model.hasAccess || recent == null) return matches;
  for (final chunk in ids.map(int.tryParse).nonNulls.slices(256)) {
    final matching = recent.copyWith(
      filterOption: CustomFilter.sql(
        where: "${CustomColumns.android.id} IN (${chunk.join(",")})",
        orderBy: [OrderByItem.asc(CustomColumns.android.id)],
      ),
    );
    final assets = await model.library.readFirstPage(matching, chunk.length);
    if (!isCurrent()) return {};
    for (final asset in assets) {
      if (_matchesType(asset, recent.type)) {
        matches[asset.id] = asset;
      }
    }
  }
  return matches;
}
