import 'package:ente_events/event_bus.dart';
import 'package:ente_ui/utils/dialog_util.dart';
import 'package:ente_ui/utils/toast_util.dart';
import 'package:flutter/material.dart';
import 'package:locker/events/collections_updated_event.dart';
import 'package:locker/l10n/l10n.dart';
import 'package:locker/services/configuration.dart';
import 'package:locker/services/db/locker_db.dart';
import 'package:locker/services/files/download/file_downloader.dart';
import 'package:locker/services/files/offline/offline_file_storage.dart';
import 'package:locker/services/files/sync/models/file.dart';
import 'package:locker/services/info_file_service.dart';
import 'package:logging/logging.dart';

/// Handles Locker's explicit per-file offline save flow.
///
/// A file is marked offline only after the encrypted blob has been saved on
/// this device.
class OfflineFilesService {
  OfflineFilesService._privateConstructor();

  static const _cachedFileCleanupAge = Duration(hours: 12);

  static final OfflineFilesService instance =
      OfflineFilesService._privateConstructor();

  final Logger _logger = Logger('OfflineFilesService');

  Future<void> init() async {
    _logger.fine('Cleaning up stale offline file copies');
    await cleanupStaleOfflineFileCopies(olderThan: _cachedFileCleanupAge);
  }

  /// Shared files and info records are intentionally excluded from offline save.
  bool _canMarkOffline(EnteFile file) {
    final currentUserID = Configuration.instance.getUserID();
    return file.uploadedFileID != null &&
        file.fileDecryptionHeader != null &&
        file.ownerID == currentUserID &&
        !InfoFileService.instance.isInfoFile(file);
  }

  List<EnteFile> getEligibleFiles(Iterable<EnteFile> files) {
    final eligibleFilesById = <int, EnteFile>{};

    for (final file in files) {
      final fileId = file.uploadedFileID;
      if (fileId == null || !_canMarkOffline(file)) {
        continue;
      }
      eligibleFilesById[fileId] = file;
    }

    return eligibleFilesById.values.toList();
  }

  /// Downloads the encrypted blob and marks the file offline on success.
  Future<bool> markFilesOffline(
    BuildContext context,
    Iterable<EnteFile> files,
  ) async {
    final eligibleFiles = getEligibleFiles(files);
    _logger.info(
      'Mark offline requested for ${eligibleFiles.length} eligible files',
    );

    if (eligibleFiles.isEmpty) {
      _logger.fine('No eligible files to mark offline');
      return false;
    }

    final total = eligibleFiles.length;
    final savingOffline = context.mounted ? context.l10n.savingOffline : null;
    final dialog = savingOffline == null
        ? null
        : createProgressDialog(
            context,
            total == 1 ? savingOffline : '$savingOffline 0/$total',
            isDismissible: false,
          );

    var successCount = 0;
    var failureCount = 0;

    await dialog?.show();

    try {
      for (var index = 0; index < eligibleFiles.length; index++) {
        final file = eligibleFiles[index];
        final fileID = file.uploadedFileID!;
        final currentStep = index + 1;

        if (context.mounted && dialog != null) {
          dialog.update(
            message: total == 1
                ? savingOffline
                : '$savingOffline $currentStep/$total',
          );
        }

        final alreadyHasOfflineCopy =
            LockerDB.instance.isFileMarkedOffline(file) &&
            await getCurrentOfflineEncryptedCopy(file) != null;
        if (alreadyHasOfflineCopy) {
          _logger.fine('File $fileID already available offline');
          successCount += 1;
          continue;
        }

        try {
          final didMarkFile = await _ensureOfflineCopyAndMark(file);
          if (didMarkFile) {
            _logger.info('Marked file $fileID available offline');
            successCount += 1;
            continue;
          }

          failureCount += 1;
        } catch (e, s) {
          failureCount += 1;
          _logger.warning(
            'Failed to mark file $fileID available offline',
            e,
            s,
          );
          await _clearOfflineState([fileID], removeWorkingCopies: false);
        }
      }
    } finally {
      try {
        await dialog?.hide();
      } catch (_) {}
    }

    _logger.info(
      'Mark offline completed: success=$successCount failure=$failureCount',
    );

    if (successCount > 0) {
      Bus.instance.fire(
        CollectionsUpdatedEvent('offline_availability_changed'),
      );
    }

    if (!context.mounted) {
      return successCount > 0;
    }

    if (failureCount == 0) {
      showToast(context, context.l10n.filesAvailableOffline(successCount));
    } else if (successCount > 0) {
      showToast(
        context,
        context.l10n.filesAvailableOfflinePartial(successCount, failureCount),
      );
    } else {
      showToast(context, context.l10n.failedToSaveFilesOffline(failureCount));
    }

    return successCount > 0;
  }

  /// Clears offline state for the selected files on this device.
  Future<bool> unmarkFilesOffline(
    BuildContext context,
    Iterable<EnteFile> files,
  ) async {
    final eligibleFiles = getEligibleFiles(files);
    _logger.info(
      'Remove offline requested for ${eligibleFiles.length} eligible files',
    );

    if (eligibleFiles.isEmpty) {
      _logger.fine('No eligible files to remove from offline');
      return false;
    }

    final fileIDsToUnmark = <int>{};
    for (final file in eligibleFiles) {
      final fileID = file.uploadedFileID!;
      final hasOfflineCopy = await getCurrentOfflineEncryptedCopy(file) != null;
      if (!LockerDB.instance.isFileMarkedOffline(file) && !hasOfflineCopy) {
        continue;
      }
      fileIDsToUnmark.add(fileID);
    }

    final changedCount = fileIDsToUnmark.length;
    _logger.fine('Removing offline state for $changedCount files');
    await _clearOfflineState(fileIDsToUnmark);

    if (changedCount > 0) {
      Bus.instance.fire(
        CollectionsUpdatedEvent('offline_availability_changed'),
      );
    }

    if (changedCount == 0 || !context.mounted) {
      return changedCount > 0;
    }

    showToast(context, context.l10n.filesRemovedFromOffline(changedCount));
    return true;
  }

  Future<void> _clearOfflineState(
    Iterable<int> fileIDs, {
    bool removeWorkingCopies = true,
  }) async {
    final ids = fileIDs.toSet();
    if (ids.isEmpty) {
      return;
    }

    _logger.fine(
      'Clearing offline state for ${ids.length} files'
      ' (removeWorkingCopies=$removeWorkingCopies)',
    );

    await LockerDB.instance.setFilesMarkedOffline(ids, false);
    await removeOfflineFileCopiesFromDisk(
      ids,
      removeWorkingCopies: removeWorkingCopies,
    );
  }

  Future<void> cleanupInactiveOfflineFiles() async {
    final staleFileIDs = await LockerDB.instance.getStaleOfflineMarkedFileIDs();
    if (staleFileIDs.isEmpty) {
      return;
    }

    _logger.info(
      'Clearing offline state for ${staleFileIDs.length} stale files after sync',
    );
    await _clearOfflineState(staleFileIDs);
  }

  /// Downloads first, then writes the local offline mark if the file is still
  /// active in the current library view.
  Future<bool> _ensureOfflineCopyAndMark(EnteFile file) async {
    final fileID = file.uploadedFileID!;
    await ensureEncryptedOfflineCopy(file);

    if (!await LockerDB.instance.hasActiveFile(fileID)) {
      _logger.warning(
        'Skipping offline mark for file $fileID because it is no longer active',
      );
      await _clearOfflineState([fileID], removeWorkingCopies: false);
      return false;
    }

    await LockerDB.instance.setFilesMarkedOffline([fileID], true);
    return true;
  }
}
