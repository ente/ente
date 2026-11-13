import "package:photos/models/social/feed_item.dart";

typedef FeedItemsCacheKey = ({
  int userID,
  int limit,
  bool includeSharedPhotos,
  bool verifyFileExistence,
});

class FeedItemsCache {
  FeedItemsCache({required this.ttl});

  final Duration ttl;

  Future<List<FeedItem>>? _inFlightFuture;
  FeedItemsCacheKey? _inFlightKey;
  List<FeedItem>? _lastItems;
  FeedItemsCacheKey? _lastKey;
  int? _lastItemsAtMs;
  int _generation = 0;

  Future<List<FeedItem>> getOrCompute(
    FeedItemsCacheKey key,
    Future<List<FeedItem>> Function() compute,
  ) async {
    if (_inFlightFuture != null && _inFlightKey == key) {
      return _inFlightFuture!;
    }

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final lastItemsAtMs = _lastItemsAtMs;
    if (_lastItems != null &&
        _lastKey == key &&
        lastItemsAtMs != null &&
        nowMs - lastItemsAtMs <= ttl.inMilliseconds) {
      return List<FeedItem>.from(_lastItems!);
    }

    final generation = _generation;
    final future = compute();
    _inFlightFuture = future;
    _inFlightKey = key;

    try {
      final items = await future;
      if (generation == _generation) {
        _lastItems = List<FeedItem>.from(items);
        _lastKey = key;
        _lastItemsAtMs = DateTime.now().millisecondsSinceEpoch;
      }
      return items;
    } finally {
      if (identical(_inFlightFuture, future)) {
        _inFlightFuture = null;
        _inFlightKey = null;
      }
    }
  }

  void clear() {
    _generation++;
    _inFlightFuture = null;
    _inFlightKey = null;
    _lastItems = null;
    _lastKey = null;
    _lastItemsAtMs = null;
  }
}
