import "package:photos/models/backup/backup_item_status.dart";
import "package:photos/models/file/file.dart";

class BackupItem {
  final BackupItemStatus status;
  final EnteFile file;
  final int collectionID;
  final Object? error;
  final int? progressPercent;

  BackupItem({
    required this.status,
    required this.file,
    required this.collectionID,
    Object? error,
    int? progressPercent,
  }) : error = status == BackupItemStatus.retry ? error : null,
       progressPercent = status == BackupItemStatus.uploading
           ? progressPercent
           : null;

  BackupItem withStatus(BackupItemStatus status, {Object? error}) {
    return BackupItem(
      status: status,
      file: file,
      collectionID: collectionID,
      error: error,
    );
  }

  BackupItem withUploadProgress(int progressPercent) {
    if (status != BackupItemStatus.uploading) {
      throw StateError("Only an uploading backup can report progress");
    }
    return BackupItem(
      status: status,
      file: file,
      collectionID: collectionID,
      progressPercent: progressPercent,
    );
  }

  @override
  String toString() {
    return 'BackupItem(status: $status, file: $file, collectionID: $collectionID, error: $error, progressPercent: $progressPercent)';
  }

  @override
  bool operator ==(covariant BackupItem other) {
    if (identical(this, other)) return true;

    return other.status == status &&
        other.file == file &&
        other.collectionID == collectionID &&
        other.error == error &&
        other.progressPercent == progressPercent;
  }

  @override
  int get hashCode {
    return status.hashCode ^
        file.hashCode ^
        collectionID.hashCode ^
        error.hashCode ^
        progressPercent.hashCode;
  }
}
