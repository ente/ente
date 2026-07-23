import 'package:photos/models/api/memory_share/memory_share.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/file/file.dart';

class CollectionWithThumbnail {
  final Collection collection;
  final EnteFile? thumbnail;

  CollectionWithThumbnail(this.collection, this.thumbnail);
}

class SharedCollections {
  final List<Collection> outgoing;
  final List<Collection> incoming;
  final List<Collection> quickLinks;

  SharedCollections(this.outgoing, this.incoming, this.quickLinks);

  static SharedCollections empty() {
    return SharedCollections([], [], []);
  }
}

class SharedCollectionsAndMemoryLinks {
  final SharedCollections collections;
  final List<MemoryShare> memoryLinks;

  SharedCollectionsAndMemoryLinks(this.collections, this.memoryLinks);

  static SharedCollectionsAndMemoryLinks empty() {
    return SharedCollectionsAndMemoryLinks(SharedCollections.empty(), []);
  }
}
