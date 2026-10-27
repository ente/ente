import "package:flutter/foundation.dart";
import "package:logging/logging.dart";
import "package:photos/events/sync_status_update_event.dart";

class LargeBackupSessionTracker extends ChangeNotifier {
  static final _logger = Logger("LargeBackupSessionTracker");
  static const int minimumFileCount = 50;

  bool _isEligible = false;
  bool _isUploading = false;
  int _completedCount = 0;
  int _totalCount = 0;
  bool _isStandbyScreenActive = false;

  bool get isActive => _isUploading && _isEligible;

  bool get isUploading => _isUploading;

  int get completedCount => _completedCount;

  int get totalCount => _totalCount;

  bool get isStandbyScreenActive => _isStandbyScreenActive;

  void setStandbyScreenActive(bool value) {
    _isStandbyScreenActive = value;
  }

  void update(SyncStatusUpdate event) {
    final wasActive = isActive;
    final wasUploading = _isUploading;
    final previousCompletedCount = _completedCount;
    final previousTotalCount = _totalCount;

    switch (event.status) {
      case SyncStatus.preparingForUpload:
        final total = event.total ?? 0;
        _isUploading = total > 0;
        _isEligible = _isEligible || total >= minimumFileCount;
        _completedCount = 0;
        _totalCount = total;
        break;
      case SyncStatus.inProgress:
        final total = event.total ?? 0;
        if (total == 0) {
          break;
        }
        _completedCount = (event.completed ?? 0).clamp(0, total);
        _totalCount = total;
        break;
      case SyncStatus.completedBackup:
      case SyncStatus.error:
      case SyncStatus.paused:
        _reset();
        break;
      case SyncStatus.startedFirstGalleryImport:
      case SyncStatus.completedFirstGalleryImport:
      case SyncStatus.applyingRemoteDiff:
        break;
    }

    if (event.status == SyncStatus.preparingForUpload ||
        wasActive != isActive ||
        wasUploading != _isUploading) {
      _logger.info(
        "status=${event.status.name}, completed=$_completedCount, "
        "total=$_totalCount, "
        "eligible=$_isEligible, uploading=$_isUploading, "
        "active=$isActive",
      );
    }

    if (wasActive != isActive ||
        wasUploading != _isUploading ||
        previousCompletedCount != _completedCount ||
        previousTotalCount != _totalCount) {
      notifyListeners();
    }
  }

  void _reset() {
    _isEligible = false;
    _isUploading = false;
    _completedCount = 0;
    _totalCount = 0;
  }
}
