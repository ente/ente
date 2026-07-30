import 'package:flutter_test/flutter_test.dart';
import 'package:photos/models/backup/backup_item.dart';
import 'package:photos/models/backup/backup_item_status.dart';
import 'package:photos/models/file/file.dart';

void main() {
  test('copyWith can explicitly clear a retry error', () {
    final error = StateError('retry');
    final retryItem = BackupItem(
      status: BackupItemStatus.retry,
      file: EnteFile(),
      collectionID: 1,
      error: error,
    );

    expect(retryItem.copyWith().error, same(error));
    expect(retryItem.copyWith(error: null).error, isNull);

    const replacementError = Object();
    expect(
      retryItem.copyWith(error: replacementError).error,
      same(replacementError),
    );
  });

  test('non-retry statuses cannot retain an error', () {
    final retryItem = BackupItem(
      status: BackupItemStatus.retry,
      file: EnteFile(),
      collectionID: 1,
      error: StateError('retry'),
    );

    final uploadingItem = retryItem.copyWith(
      status: BackupItemStatus.uploading,
    );

    expect(uploadingItem.error, isNull);
  });

  test('normalizes an error on a non-retry item', () {
    final item = BackupItem(
      status: BackupItemStatus.uploading,
      file: EnteFile(),
      collectionID: 1,
      error: StateError('unexpected'),
    );

    expect(item.error, isNull);
  });
}
