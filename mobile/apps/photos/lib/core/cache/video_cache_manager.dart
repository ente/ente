import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class VideoCacheManager {
  static const key = 'cached-video-data';

  static CacheManager instance = CacheManager(
    Config(key, maxNrOfCacheObjects: 50, stalePeriod: const Duration(days: 3)),
  );
}
