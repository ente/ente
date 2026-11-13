import 'dart:typed_data';

import 'package:photos/core/cache/lru_map.dart';
import 'package:photos/core/constants.dart';
import 'package:photos/models/file/file.dart';

class ThumbnailInMemoryLruCache {
  static final LRUMap<String, Uint8List?> _map = LRUMap(1000);

  static Uint8List? get(EnteFile enteFile, [int? size]) {
    return _map.get(
      enteFile.cacheKey() +
          "_" +
          (size != null ? size.toString() : thumbnailLargeSize.toString()),
    );
  }

  static void put(EnteFile enteFile, Uint8List? imageData, [int? size]) {
    _map.put(
      enteFile.cacheKey() +
          "_" +
          (size != null ? size.toString() : thumbnailLargeSize.toString()),
      imageData,
    );
  }

  static void clearCache(EnteFile enteFile) {
    _map.remove(enteFile.cacheKey() + "_" + thumbnailLargeSize.toString());
    _map.remove(enteFile.cacheKey() + "_" + thumbnailSmallSize.toString());
  }

  static void clearAll() {
    _map.clear();
  }
}
