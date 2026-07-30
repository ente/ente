import "package:photos/models/backup/backup_item_status.dart";
import "package:photos/models/file/file.dart";

class _PreserveError {
  const _PreserveError();
}

class BackupItem {
  static const _preserveError = _PreserveError();

  final BackupItemStatus status;
  final EnteFile file;
  final int collectionID;
  final Object? error;

  BackupItem({
    required this.status,
    required this.file,
    required this.collectionID,
    Object? error,
  }) : error = status == BackupItemStatus.retry ? error : null;

  BackupItem copyWith({
    BackupItemStatus? status,
    EnteFile? file,
    int? collectionID,
    Object? error = _preserveError,
  }) {
    final nextStatus = status ?? this.status;
    final nextError = identical(error, _preserveError) ? this.error : error;
    return BackupItem(
      status: nextStatus,
      file: file ?? this.file,
      collectionID: collectionID ?? this.collectionID,
      error: nextStatus == BackupItemStatus.retry ? nextError : null,
    );
  }

  @override
  String toString() {
    return 'BackupItem(status: $status, file: $file, collectionID: $collectionID, error: $error)';
  }

  @override
  bool operator ==(covariant BackupItem other) {
    if (identical(this, other)) return true;

    return other.status == status &&
        other.file == file &&
        other.collectionID == collectionID &&
        other.error == error;
  }

  @override
  int get hashCode {
    return status.hashCode ^
        file.hashCode ^
        collectionID.hashCode ^
        error.hashCode;
  }
}
