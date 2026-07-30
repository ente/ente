import 'dart:async';
import 'dart:collection';

import 'package:collection/collection.dart';
import 'package:photos/models/backup/backup_item.dart';
import 'package:photos/models/backup/backup_item_status.dart';
import 'package:photos/models/backup/backup_items_change.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';

typedef BackupItemsChanged = void Function(BackupItemsChange change);

class UploadQueue {
  UploadQueue(this._onBackupItemsChanged);

  final BackupItemsChanged _onBackupItemsChanged;
  final _items = <String, UploadQueueItem>{};
  final _backupItems = <String, BackupItem>{};
  final _backupOwners = <String, Object>{};

  Map<String, BackupItem>? _backupItemsSnapshot;
  int _activeUploads = 0;
  int _activeVideoUploads = 0;
  int _sessionUploadCount = 0;

  Map<String, BackupItem> get backupItems => _backupItemsSnapshot ??=
      UnmodifiableMapView(LinkedHashMap.of(_backupItems));
  bool get hasPendingUploads => _items.isNotEmpty;
  bool get isUploading => _activeUploads > 0;
  int get sessionUploadCount => _sessionUploadCount;

  UploadQueueRequest add(EnteFile file, int collectionID) {
    final localID = file.localID!;
    _sessionUploadCount++;
    final existingItem = _items[localID];
    if (existingItem != null) {
      final isSameCollection = existingItem.collectionID == collectionID;
      if (isSameCollection) {
        _sessionUploadCount--;
      }
      return UploadQueueRequest.existing(existingItem, isSameCollection);
    }

    final completer = Completer<EnteFile>();
    final item = UploadQueueItem(file, collectionID, completer);
    _items[localID] = item;
    _backupItems[localID] = BackupItem(
      status: BackupItemStatus.inQueue,
      file: file,
      collectionID: collectionID,
    );
    _backupOwners[localID] = item;
    _notifyBackupItemsChanged(upserts: {localID: _backupItems[localID]!});
    return UploadQueueRequest.added(item);
  }

  void clear(Error reason) {
    final pendingUploadIDs = _items.entries
        .where((entry) => entry.value._status == _UploadStatus.notStarted)
        .map((entry) => entry.key)
        .toList();
    _removePendingUploads(pendingUploadIDs, reason);
    _sessionUploadCount = 0;
  }

  int removeWhere(bool Function(EnteFile) predicate, Error reason) {
    final pendingUploadIDs = _items.entries
        .where(
          (entry) =>
              entry.value._status == _UploadStatus.notStarted &&
              predicate(entry.value.file),
        )
        .map((entry) => entry.key)
        .toList();
    _removePendingUploads(pendingUploadIDs, reason);
    _sessionUploadCount -= pendingUploadIDs.length;
    _resetSessionUploadCountIfEmpty();
    return pendingUploadIDs.length;
  }

  UploadQueueItem? startNext({
    required int maximumConcurrentUploads,
    required int maximumConcurrentVideoUploads,
  }) {
    if (_items.isEmpty) {
      _sessionUploadCount = 0;
      return null;
    }
    if (_activeUploads >= maximumConcurrentUploads) {
      return null;
    }

    var pendingItem = _items.values.firstWhereOrNull(
      (item) => item._status == _UploadStatus.notStarted,
    );
    if (pendingItem?.file.fileType == FileType.video &&
        _activeVideoUploads >= maximumConcurrentVideoUploads) {
      pendingItem = _items.values.firstWhereOrNull(
        (item) =>
            item._status == _UploadStatus.notStarted &&
            item.file.fileType != FileType.video,
      );
    }
    if (pendingItem == null) {
      return null;
    }

    pendingItem._status = _UploadStatus.inProgress;
    _activeUploads++;
    if (pendingItem.file.fileType == FileType.video) {
      _activeVideoUploads++;
    }
    _setBackupStatus(
      pendingItem.file.localID!,
      pendingItem,
      BackupItemStatus.uploading,
    );
    return pendingItem;
  }

  void finishAttempt(UploadQueueItem item) {
    _activeUploads--;
    if (item.file.fileType == FileType.video) {
      _activeVideoUploads--;
    }
  }

  void complete(UploadQueueItem item, EnteFile uploadedFile) {
    final localID = item.file.localID!;
    if (!identical(_items[localID], item)) {
      return;
    }
    _items.remove(localID);
    _resetSessionUploadCountIfEmpty();
    item.completer.complete(uploadedFile);
    _backupItems.remove(localID);
    _backupOwners.remove(localID);
    _notifyBackupItemsChanged(removedLocalIDs: {localID});
  }

  Future<EnteFile> moveToBackground(UploadQueueItem item) {
    final localID = item.file.localID!;
    if (!identical(_items[localID], item)) {
      return item.completer.future;
    }
    item._status = _UploadStatus.inBackground;
    _setBackupStatus(localID, item, BackupItemStatus.inBackground);
    return item.completer.future;
  }

  void fail(UploadQueueItem item, Object error) {
    final localID = item.file.localID!;
    if (!identical(_items[localID], item)) {
      return;
    }
    _items.remove(localID);
    _resetSessionUploadCountIfEmpty();
    item.completer.completeError(error);
    _setBackupStatus(localID, item, BackupItemStatus.retry, error: error);
  }

  Object? backupOwner(String localID) => _backupOwners[localID];

  void markBackupUploading(Object owner, String localID) {
    if (_backupItems[localID]?.status != BackupItemStatus.uploading) {
      _setBackupStatusIfOwned(localID, owner, BackupItemStatus.uploading);
    }
  }

  void markBackupUploaded(Object owner, String localID) {
    if (!identical(_backupOwners[localID], owner)) {
      return;
    }
    if (_items.containsKey(localID)) {
      _setBackupStatus(localID, owner, BackupItemStatus.uploaded);
    } else if (_backupItems.remove(localID) != null) {
      _backupOwners.remove(localID);
      _notifyBackupItemsChanged(removedLocalIDs: {localID});
    }
  }

  void markBackupForRetry(Object owner, String localID, Object error) {
    _setBackupStatusIfOwned(
      localID,
      owner,
      BackupItemStatus.retry,
      error: error,
    );
  }

  List<UploadQueueItem> get backgroundItems => _items.values
      .where((item) => item._status == _UploadStatus.inBackground)
      .toList();

  void _removePendingUploads(List<String> localIDs, Error reason) {
    if (localIDs.isEmpty) {
      return;
    }
    final upserts = <String, BackupItem>{};
    for (final localID in localIDs) {
      _items.remove(localID)?.completer.completeError(reason);
      final updatedItem = _setBackupStatusWithoutNotification(
        localID,
        _backupOwners[localID]!,
        BackupItemStatus.retry,
        error: reason,
      );
      if (updatedItem != null) {
        upserts[localID] = updatedItem;
      }
    }
    _notifyBackupItemsChanged(upserts: upserts);
  }

  void _setBackupStatus(
    String localID,
    Object owner,
    BackupItemStatus status, {
    Object? error,
  }) {
    final updatedItem = _setBackupStatusWithoutNotification(
      localID,
      owner,
      status,
      error: error,
    );
    if (updatedItem != null) {
      _notifyBackupItemsChanged(upserts: {localID: updatedItem});
    }
  }

  void _setBackupStatusIfOwned(
    String localID,
    Object owner,
    BackupItemStatus status, {
    Object? error,
  }) {
    if (!identical(_backupOwners[localID], owner)) {
      return;
    }
    _setBackupStatus(localID, owner, status, error: error);
  }

  BackupItem? _setBackupStatusWithoutNotification(
    String localID,
    Object owner,
    BackupItemStatus status, {
    Object? error,
  }) {
    if (!identical(_backupOwners[localID], owner)) {
      return null;
    }
    final updatedItem = _backupItems[localID]!.copyWith(
      status: status,
      error: error,
    );
    _backupItems[localID] = updatedItem;
    return updatedItem;
  }

  void _notifyBackupItemsChanged({
    Map<String, BackupItem> upserts = const {},
    Set<String> removedLocalIDs = const {},
  }) {
    _backupItemsSnapshot = null;
    _onBackupItemsChanged(
      BackupItemsChange(upserts: upserts, removedLocalIDs: removedLocalIDs),
    );
  }

  void _resetSessionUploadCountIfEmpty() {
    if (_items.isEmpty) {
      _sessionUploadCount = 0;
    }
  }
}

class UploadQueueRequest {
  UploadQueueRequest.added(this.item)
    : disposition = UploadQueueDisposition.added;

  UploadQueueRequest.existing(this.item, bool isSameCollection)
    : disposition = isSameCollection
          ? UploadQueueDisposition.sameCollection
          : UploadQueueDisposition.otherCollection;

  final UploadQueueItem item;
  final UploadQueueDisposition disposition;
}

enum UploadQueueDisposition { added, sameCollection, otherCollection }

class UploadQueueItem {
  UploadQueueItem(this.file, this.collectionID, this.completer);

  final EnteFile file;
  final int collectionID;
  final Completer<EnteFile> completer;
  _UploadStatus _status = _UploadStatus.notStarted;
}

enum _UploadStatus { notStarted, inProgress, inBackground }
