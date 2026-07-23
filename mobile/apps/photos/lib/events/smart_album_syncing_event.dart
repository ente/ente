import 'package:photos/events/event.dart';

class SmartAlbumSyncingEvent extends Event {
  int? collectionId;
  bool isSyncing;

  SmartAlbumSyncingEvent({this.collectionId, this.isSyncing = false});
}
