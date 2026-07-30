import 'package:flutter_test/flutter_test.dart';
import 'package:photos/models/backup/backup_item.dart';
import 'package:photos/models/backup/backup_item_status.dart';
import 'package:photos/models/backup/backup_items_change.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import 'package:photos/module/upload/service/upload_queue.dart';

void main() {
  test('same-collection requests share one item and future', () {
    final changes = <BackupItemsChange>[];
    final queue = UploadQueue(changes.add);
    final file = _file('local-1');

    final added = queue.add(file, 10);
    final sameCollection = queue.add(file, 10);

    expect(added.disposition, UploadQueueDisposition.added);
    expect(sameCollection.disposition, UploadQueueDisposition.sameCollection);
    expect(identical(added.item, sameCollection.item), isTrue);
    expect(
      identical(
        added.item.completer.future,
        sameCollection.item.completer.future,
      ),
      isTrue,
    );
    expect(queue.sessionUploadCount, 1);
    expect(changes, hasLength(1));
    expect(changes.single.upserts.keys, ['local-1']);
    expect(changes.single.removedLocalIDs, isEmpty);
    expect(
      () => changes.single.upserts['other'] =
          changes.single.upserts.values.single,
      throwsUnsupportedError,
    );
    expect(
      () => changes.single.removedLocalIDs.add('other'),
      throwsUnsupportedError,
    );
  });

  test('different-collection requests wait on the same queued item', () {
    final queue = UploadQueue((_) {});
    final file = _file('local-1');

    final added = queue.add(file, 10);
    final otherCollection = queue.add(file, 20);

    expect(otherCollection.disposition, UploadQueueDisposition.otherCollection);
    expect(otherCollection.item, same(added.item));
    expect(
      identical(
        added.item.completer.future,
        otherCollection.item.completer.future,
      ),
      isTrue,
    );
    expect(queue.sessionUploadCount, 2);
  });

  test('selects non-video work in FIFO order', () {
    final queue = UploadQueue((_) {});
    final first = queue.add(_file('first'), 1).item;
    final second = queue.add(_file('second'), 1).item;
    final third = queue.add(_file('third'), 1).item;

    expect(_start(queue), same(first));
    expect(_start(queue), same(second));
    expect(_start(queue), same(third));
  });

  test('enforces total and video limits while allowing image bypass', () {
    final queue = UploadQueue((_) {});
    final firstVideo = queue.add(_file('video-1', FileType.video), 1).item;
    final secondVideo = queue.add(_file('video-2', FileType.video), 1).item;
    final thirdVideo = queue.add(_file('video-3', FileType.video), 1).item;
    final firstImage = queue.add(_file('image-1'), 1).item;
    final secondImage = queue.add(_file('image-2'), 1).item;
    final thirdImage = queue.add(_file('image-3'), 1).item;

    expect(_start(queue), same(firstVideo));
    expect(_start(queue), same(secondVideo));
    expect(_start(queue), same(firstImage));
    expect(_start(queue), same(secondImage));
    expect(_start(queue), isNull);

    queue.finishAttempt(firstVideo);
    expect(_start(queue), same(thirdVideo));
    expect(_start(queue), isNull);

    queue.finishAttempt(firstImage);
    expect(_start(queue), same(thirdImage));
    expect(queue.isUploading, isTrue);
    expect(queue.backupItems['video-3']!.status, BackupItemStatus.uploading);

    queue.finishAttempt(secondVideo);
    queue.finishAttempt(secondImage);
    queue.finishAttempt(thirdVideo);
    queue.finishAttempt(thirdImage);
    expect(queue.isUploading, isFalse);
  });

  test('cancels pending items with one backup notification', () async {
    final changes = <BackupItemsChange>[];
    final queue = UploadQueue(changes.add);
    final active = queue.add(_file('active'), 1).item;
    final firstPending = queue.add(_file('pending-1'), 1).item;
    final secondPending = queue.add(_file('pending-2'), 1).item;
    _start(queue);
    final error = _QueueError();
    final firstResult = expectLater(
      firstPending.completer.future,
      throwsA(error),
    );
    final secondResult = expectLater(
      secondPending.completer.future,
      throwsA(error),
    );
    final notificationsBeforeRemoval = changes.length;

    final removed = queue.removeWhere((_) => true, error);

    expect(removed, 2);
    expect(changes.length, notificationsBeforeRemoval + 1);
    expect(changes.last.upserts.keys, ['pending-1', 'pending-2']);
    expect(changes.last.removedLocalIDs, isEmpty);
    expect(queue.hasPendingUploads, isTrue);
    expect(queue.backupItems['active']!.status, BackupItemStatus.uploading);
    expect(queue.backupItems['pending-1']!.status, BackupItemStatus.retry);
    expect(queue.backupItems['pending-2']!.status, BackupItemStatus.retry);
    await firstResult;
    await secondResult;
    queue.finishAttempt(active);
  });

  test('stale transitions cannot mutate a newer request', () async {
    final queue = UploadQueue((_) {});
    final firstItem = queue.add(_file('same-local'), 1).item;
    expect(_start(queue), same(firstItem));
    final firstError = _QueueError();
    final firstResult = expectLater(
      firstItem.completer.future,
      throwsA(firstError),
    );
    queue.fail(firstItem, firstError);
    queue.finishAttempt(firstItem);
    await firstResult;

    final secondItem = queue.add(_file('same-local'), 1).item;
    queue.complete(firstItem, _file('uploaded-old'));
    queue.markBackupForRetry(firstItem, 'same-local', _QueueError());

    expect(queue.hasPendingUploads, isTrue);
    expect(queue.backupItems['same-local']!.status, BackupItemStatus.inQueue);
    expect(_start(queue), same(secondItem));

    final uploadedFile = _file('uploaded-new');
    queue.complete(secondItem, uploadedFile);
    queue.finishAttempt(secondItem);
    expect(await secondItem.completer.future, same(uploadedFile));
    expect(queue.backupItems, isEmpty);
  });

  test('emits removals without rebuilding full backup snapshots', () async {
    final changes = <BackupItemsChange>[];
    final queue = UploadQueue(changes.add);
    final item = queue.add(_file('local-1'), 1).item;
    final snapshotBeforeRemoval = queue.backupItems;
    expect(_start(queue), same(item));

    final uploadedFile = _file('uploaded');
    queue.complete(item, uploadedFile);
    queue.finishAttempt(item);

    expect(changes.last.upserts, isEmpty);
    expect(changes.last.removedLocalIDs, {'local-1'});
    expect(snapshotBeforeRemoval.keys, ['local-1']);
    expect(queue.backupItems, isEmpty);
    expect(await item.completer.future, same(uploadedFile));
  });

  test('preserves insertion order in lazy immutable snapshots', () {
    final queue = UploadQueue((_) {});
    queue.add(_file('first'), 1);
    queue.add(_file('second'), 1);

    final snapshot = queue.backupItems;

    expect(snapshot.keys, ['first', 'second']);
    expect(identical(queue.backupItems, snapshot), isTrue);
    expect(() => snapshot.remove('first'), throwsUnsupportedError);

    queue.add(_file('third'), 1);
    expect(snapshot.keys, ['first', 'second']);
    expect(queue.backupItems.keys, ['first', 'second', 'third']);
    expect(identical(queue.backupItems, snapshot), isFalse);
  });

  test('deltas reconstruct the authoritative ordered snapshot', () async {
    final reducedItems = <String, BackupItem>{};
    late final UploadQueue queue;
    queue = UploadQueue((change) {
      for (final localID in change.removedLocalIDs) {
        reducedItems.remove(localID);
      }
      reducedItems.addAll(change.upserts);
      expect(reducedItems.keys, queue.backupItems.keys);
      expect(reducedItems, queue.backupItems);
    });

    final active = queue.add(_file('active'), 1).item;
    final firstPending = queue.add(_file('pending-1'), 1).item;
    final secondPending = queue.add(_file('pending-2'), 1).item;
    expect(_start(queue), same(active));

    final error = _QueueError();
    final firstResult = expectLater(
      firstPending.completer.future,
      throwsA(error),
    );
    final secondResult = expectLater(
      secondPending.completer.future,
      throwsA(error),
    );
    queue.removeWhere((file) => file.localID != 'active', error);

    final uploadedFile = _file('uploaded');
    queue.complete(active, uploadedFile);
    queue.finishAttempt(active);

    await firstResult;
    await secondResult;
    expect(await active.completer.future, same(uploadedFile));
    expect(reducedItems.keys, ['pending-1', 'pending-2']);
    expect(reducedItems, queue.backupItems);
  });

  for (final itemCount in [1000, 10000]) {
    test('$itemCount additions emit linear aggregate delta work', () {
      var notificationCount = 0;
      var upsertCount = 0;
      var removalCount = 0;
      final queue = UploadQueue((change) {
        notificationCount++;
        upsertCount += change.upserts.length;
        removalCount += change.removedLocalIDs.length;
      });

      for (var index = 0; index < itemCount; index++) {
        queue.add(_file('local-$index'), 1);
      }

      expect(notificationCount, itemCount);
      expect(upsertCount, itemCount);
      expect(removalCount, 0);
      expect(queue.backupItems, hasLength(itemCount));
    });
  }

  test('terminal completion resolves once and resets the session', () async {
    final queue = UploadQueue((_) {});
    final item = queue.add(_file('local-1'), 1).item;
    expect(_start(queue), same(item));
    var completionCount = 0;
    final result = item.completer.future.then((file) {
      completionCount++;
      return file;
    });
    final uploadedFile = _file('uploaded');

    queue.complete(item, uploadedFile);
    queue.complete(item, _file('duplicate'));
    queue.finishAttempt(item);

    expect(await result, same(uploadedFile));
    expect(completionCount, 1);
    expect(queue.sessionUploadCount, 0);
    expect(queue.hasPendingUploads, isFalse);
    expect(queue.isUploading, isFalse);
  });

  test('background completion resets the session', () async {
    final queue = UploadQueue((_) {});
    final item = queue.add(_file('local-1'), 1).item;
    expect(_start(queue), same(item));
    final result = queue.moveToBackground(item);
    queue.finishAttempt(item);

    final uploadedFile = _file('uploaded');
    queue.complete(item, uploadedFile);

    expect(await result, same(uploadedFile));
    expect(queue.backgroundItems, isEmpty);
    expect(queue.sessionUploadCount, 0);
  });

  test('terminal failure resets the session and keeps retry details', () async {
    final queue = UploadQueue((_) {});
    final item = queue.add(_file('local-1'), 1).item;
    expect(_start(queue), same(item));
    final error = _QueueError();
    final result = expectLater(item.completer.future, throwsA(same(error)));

    queue.fail(item, error);
    queue.finishAttempt(item);

    expect(queue.sessionUploadCount, 0);
    expect(queue.hasPendingUploads, isFalse);
    expect(queue.isUploading, isFalse);
    expect(queue.backupItems['local-1']!.status, BackupItemStatus.retry);
    expect(queue.backupItems['local-1']!.error, same(error));
    await result;
  });

  test('removing the final item clears deferred session intents', () async {
    final queue = UploadQueue((_) {});
    final item = queue.add(_file('local-1'), 1).item;
    queue.add(item.file, 2);
    final error = _QueueError();
    final result = expectLater(item.completer.future, throwsA(same(error)));

    expect(queue.removeWhere((_) => true, error), 1);

    expect(queue.sessionUploadCount, 0);
    expect(queue.hasPendingUploads, isFalse);
    await result;
  });

  test('moving retry back to uploading clears its error', () async {
    final queue = UploadQueue((_) {});
    final item = queue.add(_file('local-1'), 1).item;
    expect(_start(queue), same(item));
    final error = _QueueError();
    final result = expectLater(item.completer.future, throwsA(same(error)));
    queue.fail(item, error);
    queue.finishAttempt(item);
    await result;

    queue.markBackupUploading(item, 'local-1');

    expect(queue.backupItems['local-1']!.status, BackupItemStatus.uploading);
    expect(queue.backupItems['local-1']!.error, isNull);
  });
}

UploadQueueItem? _start(UploadQueue queue) {
  return queue.startNext(
    maximumConcurrentUploads: 4,
    maximumConcurrentVideoUploads: 2,
  );
}

EnteFile _file(String localID, [FileType fileType = FileType.image]) {
  return EnteFile()
    ..localID = localID
    ..fileType = fileType;
}

class _QueueError extends Error {}
