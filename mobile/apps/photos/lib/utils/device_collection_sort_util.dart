import "package:collection/collection.dart";
import "package:photos/models/device_collection.dart";
import "package:photos/settings/local_settings.dart";

void sortDeviceCollections(
  List<DeviceCollection> deviceCollections,
  AlbumSortKey sortKey,
  AlbumSortDirection sortDirection,
) {
  if (deviceCollections.length < 2) {
    return;
  }

  deviceCollections.sort((first, second) {
    var comparison = switch (sortKey) {
      AlbumSortKey.albumName => _compareByName(first, second),
      AlbumSortKey.newestPhoto => _newestPhotoTime(
        second,
      ).compareTo(_newestPhotoTime(first)),
      AlbumSortKey.lastUpdated => _updatedTime(
        second,
      ).compareTo(_updatedTime(first)),
    };
    if (comparison == 0) {
      comparison = _compareByName(first, second);
    }
    if (comparison == 0) {
      comparison = compareAsciiLowerCaseNatural(first.id, second.id);
    }
    return sortDirection == AlbumSortDirection.ascending
        ? comparison
        : -comparison;
  });
}

int _compareByName(DeviceCollection first, DeviceCollection second) {
  return compareAsciiLowerCaseNatural(first.name, second.name);
}

int _newestPhotoTime(DeviceCollection deviceCollection) {
  return deviceCollection.thumbnail?.creationTime ?? -1;
}

int _updatedTime(DeviceCollection deviceCollection) {
  if (deviceCollection.modifiedAt > 0) {
    return deviceCollection.modifiedAt;
  }
  return _newestPhotoTime(deviceCollection);
}
