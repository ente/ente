import 'package:photos/events/files_updated_event.dart';
import 'package:photos/models/file/file.dart';

class CollectionUpdatedEvent extends FilesUpdatedEvent {
  final int? collectionID;

  CollectionUpdatedEvent(
    this.collectionID,
    List<EnteFile> updatedFiles,
    String? source, {
    EventType? type,
  }) : super(
         updatedFiles,
         type: type ?? EventType.addedOrUpdated,
         source: source ?? "",
       );
}
