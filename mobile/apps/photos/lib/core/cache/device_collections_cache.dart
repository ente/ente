import 'package:logging/logging.dart';
import 'package:photos/models/device_collection.dart';

class DeviceCollectionsCache {
  static final _logger = Logger("DeviceCollectionsCache");

  static List<DeviceCollection>? _deviceCollections;
  static int _generation = 0;

  static List<DeviceCollection>? get deviceCollections => _deviceCollections;
  static int get generation => _generation;

  static void putIfCurrent(
    int generation,
    List<DeviceCollection> deviceCollections,
  ) {
    if (generation != _generation) {
      _logger.info(
        "[DeviceAlbumCache] Ignored stale cache update after logout",
      );
      return;
    }
    _deviceCollections = deviceCollections;
    _logger.info(
      "[DeviceAlbumCache] Cached ${deviceCollections.length} device albums",
    );
  }

  static void clearAll() {
    final cachedAlbumCount = _deviceCollections?.length ?? 0;
    _deviceCollections = null;
    _generation++;
    _logger.info(
      "[DeviceAlbumCache] Cleared $cachedAlbumCount cached device albums",
    );
  }
}
