import 'package:flutter_test/flutter_test.dart';
import 'package:photos/models/backup/backup_item.dart';
import 'package:photos/models/backup/backup_item_status.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import 'package:photos/module/upload/service/upload_queue.dart';

void main() {
  test('shares requests and preserves session count semantics', () {
    final snapshots = <Map<String, BackupItem>>[];
    final queue = UploadQueue(snapshots.add);
    final file = _file('local-1');

    final added = queue.add(file, 10);
    final sameCollection = queue.add(file, 10);
    final otherCollection = queue.add(file, 20);

    expect(added.disposition, UploadQueueDisposition.added);
    expect(sameCollection.disposition, UploadQueueDisposition.sameCollection);
    expect(otherCollection.disposition, UploadQueueDisposition.otherCollection);
    expect(identical(added.item, sameCollection.item), isTrue);
    expect(identical(added.item, otherCollection.item), isTrue);
    expect(queue.sessionUploadCount, 2);
    expect(snapshots, hasLength(1));
    expect(
      () => snapshots.single['other'] = snapshots.single.values.single,
      throwsUnsupportedError,
    );
  });

  test('selects FIFO work within total and video limits', () {
    final queue = UploadQueue((_) {});
    final firstVideo = queue.add(_file('video-1', FileType.video), 1).item;
    final secondVideo = queue.add(_file('video-2', FileType.video), 1).item;
    final thirdVideo = queue.add(_file('video-3', FileType.video), 1).item;
    final image = queue.add(_file('image-1'), 1).item;

    expect(_start(queue), same(firstVideo));
    expect(_start(queue), same(secondVideo));
    expect(_start(queue), same(image));
    expect(_start(queue), isNull);

    queue.finishAttempt(firstVideo);
    expect(_start(queue), same(thirdVideo));
    expect(queue.isUploading, isTrue);
    expect(queue.backupItems['video-3']!.status, BackupItemStatus.uploading);
  });

  test('cancels pending items with one backup notification', () async {
    final snapshots = <Map<String, BackupItem>>[];
    final queue = UploadQueue(snapshots.add);
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
    final notificationsBeforeRemoval = snapshots.length;

    final removed = queue.removeWhere((_) => true, error);

    expect(removed, 2);
    expect(snapshots.length, notificationsBeforeRemoval + 1);
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
