import "package:photos/models/backup/backup_item.dart";

class BackupItemsChange {
  BackupItemsChange({
    Map<String, BackupItem> upserts = const {},
    Set<String> removedLocalIDs = const {},
  }) : upserts = Map.unmodifiable(upserts),
       removedLocalIDs = Set.unmodifiable(removedLocalIDs);

  final Map<String, BackupItem> upserts;
  final Set<String> removedLocalIDs;
}
