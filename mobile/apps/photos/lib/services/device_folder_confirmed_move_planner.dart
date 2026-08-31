import 'package:photos/core/configuration.dart';
import 'package:photos/db/device_files_db.dart';
import 'package:photos/db/files_db.dart';
import 'package:photos/models/device_collection.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/module/upload/service/file_uploader.dart';
import 'package:photos/services/collections_service.dart';

class ConfirmedDeviceFolderMovePlan {
  const ConfirmedDeviceFolderMovePlan({
    required this.source,
    required this.destination,
    required this.entries,
  });

  final DeviceCollection source;
  final DeviceCollection destination;
  final List<ConfirmedDeviceFolderMoveEntry> entries;
}

class ConfirmedDeviceFolderMoveEntry {
  const ConfirmedDeviceFolderMoveEntry({
    required this.localID,
    required this.sourceCollectionID,
    required this.destinationCollectionID,
  });

  final String localID;
  final int sourceCollectionID;
  final int destinationCollectionID;
}

Set<String> selectConfirmedMoveLocalIDs({
  required Iterable<String> requestedLocalIDs,
  required String sourceFolderID,
  required Set<String> pendingLocalIDs,
  required Map<String, Set<String>> folderIDsByLocalID,
  required Map<String, int> uploadedSourceRowCounts,
}) {
  return requestedLocalIDs
      .where(
        (localID) =>
            !pendingLocalIDs.contains(localID) &&
            folderIDsByLocalID[localID]?.length == 1 &&
            folderIDsByLocalID[localID]?.single == sourceFolderID &&
            uploadedSourceRowCounts[localID] == 1,
      )
      .toSet();
}

class DeviceFolderConfirmedMovePlanner {
  DeviceFolderConfirmedMovePlanner._();

  static final instance = DeviceFolderConfirmedMovePlanner._();

  Future<ConfirmedDeviceFolderMovePlan?> planDeviceMove({
    required DeviceCollection source,
    required DeviceCollection destination,
    required Iterable<String> localIDs,
  }) async {
    final sourceCollectionID = source.collectionID;
    final destinationCollectionID = destination.collectionID;
    final ids = localIDs.toSet();
    if (ids.isEmpty ||
        !source.shouldBackup ||
        !destination.shouldBackup ||
        source.id == destination.id ||
        sourceCollectionID == null ||
        destinationCollectionID == null ||
        sourceCollectionID == destinationCollectionID ||
        sourceCollectionID == -1 ||
        destinationCollectionID == -1 ||
        !_areLinkedCollections(sourceCollectionID, destinationCollectionID)) {
      return null;
    }
    final pendingIDs = FileUploader.instance.allBackups.keys.toSet();
    final folderIDsByLocalID = <String, Set<String>>{};
    for (final entry
        in (await FilesDB.instance.getDevicePathIDToLocalIDMap()).entries) {
      for (final id in entry.value) {
        if (ids.contains(id)) {
          folderIDsByLocalID.putIfAbsent(id, () => <String>{}).add(entry.key);
        }
      }
    }
    final uploaded = await FilesDB.instance.getUploadedFilesForLocalIDs(
      ids.difference(pendingIDs),
      collectionID: sourceCollectionID,
    );
    final filesByLocalID = <String, List<EnteFile>>{};
    for (final file in uploaded) {
      final id = file.localID;
      if (id != null) filesByLocalID.putIfAbsent(id, () => []).add(file);
    }
    final eligibleLocalIDs = selectConfirmedMoveLocalIDs(
      requestedLocalIDs: ids,
      sourceFolderID: source.id,
      pendingLocalIDs: pendingIDs,
      folderIDsByLocalID: folderIDsByLocalID,
      uploadedSourceRowCounts: {
        for (final entry in filesByLocalID.entries)
          entry.key: entry.value.length,
      },
    );
    final entries = <ConfirmedDeviceFolderMoveEntry>[];
    for (final id in eligibleLocalIDs) {
      final files = filesByLocalID[id];
      if (files == null) continue;
      entries.add(
        ConfirmedDeviceFolderMoveEntry(
          localID: id,
          sourceCollectionID: sourceCollectionID,
          destinationCollectionID: destinationCollectionID,
        ),
      );
    }
    return ConfirmedDeviceFolderMovePlan(
      source: source,
      destination: destination,
      entries: entries,
    );
  }

  bool _areLinkedCollections(int sourceID, int destinationID) {
    final ownerID = Configuration.instance.getUserID();
    if (ownerID == null) return false;
    final source = CollectionsService.instance.getCollectionByID(sourceID);
    final destination = CollectionsService.instance.getCollectionByID(
      destinationID,
    );
    return source != null &&
        destination != null &&
        source.canLinkToDevicePath(ownerID) &&
        destination.canLinkToDevicePath(ownerID);
  }
}
