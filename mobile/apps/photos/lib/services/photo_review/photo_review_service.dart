import "dart:async";

import "package:collection/collection.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/core/user_config.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/photo_review_db.dart";
import "package:photos/events/photo_review_updated_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file_load_result.dart";
import "package:photos/models/photo_review/photo_review_models.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/filter/db_filters.dart";

class PhotoReviewService {
  PhotoReviewService._privateConstructor();

  static final PhotoReviewService instance =
      PhotoReviewService._privateConstructor();

  static final _logger = Logger("PhotoReviewService");

  final PhotoReviewDB _db = PhotoReviewDB.instance;

  static String fileKey(EnteFile file) {
    if (file.uploadedFileID != null) return "u:${file.uploadedFileID}";
    if (file.localID != null) return "l:${file.localID}";
    return "g:${file.generatedID}";
  }

  Future<ReviewOverview> loadOverview() async {
    final files = await _loadFiles(galleryLoadStartTime, galleryLoadEndTime);
    final decisions = await _db.getAllDecisions();
    final months = await _db.getMonthRecords();
    final index = ReviewDecisionIndex(decisions);
    await _reconcileDecisions(files, index);
    return buildOverview(files, index.records.toList(), months);
  }

  Future<ReviewMonthData> loadMonth(ReviewMonthKey key) async {
    final files = await _loadFiles(key.startMicros, key.endMicros);
    final index = ReviewDecisionIndex(
      await _db.getDecisionsForFiles(files.map(fileKey).toList(), [
        for (final file in files) ?file.localID,
      ]),
    );
    await _reconcileDecisions(files, index);
    final decisions = <String, ReviewDecision>{};
    final undoable = <(EnteFile, ReviewDecisionRecord)>[];
    for (final file in files) {
      final record = index.lookup(file);
      if (record == null || record.decision == ReviewDecision.deleted) {
        continue;
      }
      decisions[fileKey(file)] = record.decision;
      undoable.add((file, record));
    }
    undoable.sort((a, b) => a.$2.updatedAt.compareTo(b.$2.updatedAt));
    return ReviewMonthData(
      files: files,
      decisions: decisions,
      history: [for (final (file, record) in undoable) (file, record.decision)],
      record: await _db.getMonthRecord(key.key),
    );
  }

  Future<void> recordDecision(
    EnteFile file,
    ReviewMonthKey month,
    ReviewDecision decision,
  ) async {
    final now = _now();
    await _db.saveDecisions(
      [_recordFor(file, month, decision, now)],
      month.key,
      now,
    );
    _notifyUpdated();
  }

  Future<void> removeDecision(EnteFile file, ReviewMonthKey month) async {
    await _db.deleteDecision(fileKey(file), file.localID, month.key, _now());
    _notifyUpdated();
  }

  Future<void> recordDeletion(
    ReviewMonthKey month, {
    required List<EnteFile> removed,
    required List<EnteFile> kept,
  }) async {
    final now = _now();
    final freedBytes = [
      ...removed,
      ...kept,
    ].fold<int>(0, (sum, file) => sum + (file.fileSize ?? 0));
    await _db.recordDeletion(
      [
        for (final file in removed)
          _recordFor(file, month, ReviewDecision.deleted, now),
        for (final file in kept)
          _recordFor(file, month, ReviewDecision.keep, now),
      ],
      month.key,
      freedBytes,
      now,
    );
    _notifyUpdated();
  }

  Future<void> markMonthsReviewed(Iterable<ReviewMonthKey> months) async {
    await _db.markMonthsReviewed(
      months.map((month) => month.key).toList(),
      _now(),
    );
    _notifyUpdated();
  }

  Future<void> unmarkMonthReviewed(ReviewMonthKey month) async {
    await _db.unmarkMonthReviewed(month.key, _now());
    _notifyUpdated();
  }

  Future<void> resetMonths(Iterable<ReviewMonthKey> months) async {
    await _db.resetMonths(months.map((month) => month.key).toList());
    _notifyUpdated();
  }

  static ReviewOverview buildOverview(
    List<EnteFile> files,
    List<ReviewDecisionRecord> decisions,
    Map<String, ReviewMonthRecord> monthRecords,
  ) {
    final index = ReviewDecisionIndex(decisions);
    final buckets = <ReviewMonthKey, List<EnteFile>>{};
    for (final file in files) {
      final creationTime = file.creationTime;
      if (creationTime == null) continue;
      buckets
          .putIfAbsent(ReviewMonthKey.fromCreationTime(creationTime), () => [])
          .add(file);
    }
    final summaries = <ReviewMonthSummary>[];
    for (final entry in buckets.entries) {
      var decided = 0;
      var queued = 0;
      for (final file in entry.value) {
        final record = index.lookup(file);
        if (record == null || record.decision == ReviewDecision.deleted) {
          continue;
        }
        decided++;
        if (record.decision == ReviewDecision.queued) queued++;
      }
      final record = monthRecords[entry.key.key];
      summaries.add(
        ReviewMonthSummary(
          key: entry.key,
          cover: entry.value.first,
          totalCount: entry.value.length,
          decidedCount: decided,
          queuedCount: queued,
          markedReviewed: record?.markedReviewed ?? false,
          lastReviewedAt: record?.updatedAt ?? 0,
        ),
      );
    }
    summaries.sort((a, b) => a.key.compareTo(b.key));
    final byYear = <int, List<ReviewMonthSummary>>{};
    for (final summary in summaries) {
      byYear.putIfAbsent(summary.key.year, () => []).add(summary);
    }
    final years = [
      for (final year in byYear.keys.toList()..sort((a, b) => b.compareTo(a)))
        ReviewYearSummary(year: year, months: byYear[year]!),
    ];
    return ReviewOverview(years: years, bannerMonths: _bannerMonths(summaries));
  }

  static List<ReviewMonthSummary> _bannerMonths(
    List<ReviewMonthSummary> months,
  ) {
    final inProgress =
        months
            .where((month) => month.state == ReviewMonthState.inProgress)
            .toList()
          ..sort((a, b) => b.lastReviewedAt.compareTo(a.lastReviewedAt));
    final untouched = months.lastWhereOrNull(
      (month) => month.state == ReviewMonthState.normal,
    );
    return [...inProgress, ?untouched];
  }

  static ReviewMonthKey? nextMonthToReview(
    ReviewOverview overview,
    ReviewMonthKey after,
  ) {
    final months = overview.months.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    for (final month in months) {
      if (month.key.compareTo(after) < 0 && !month.isCompleted) {
        return month.key;
      }
    }
    for (final month in months) {
      if (month.key != after && !month.isCompleted) return month.key;
    }
    return null;
  }

  Future<List<EnteFile>> _loadFiles(int startMicros, int endMicros) async {
    final ownerID = Configuration.instance.getUserIDV2();
    final filterOptions = DBFilterOptions(
      hideIgnoredForUpload: true,
      dedupeUploadID: true,
      ignoredCollectionIDs: CollectionsService.instance
          .archivedOrHiddenCollectionIds(),
      ignoreSavedFiles: true,
      ignoreSharedItems: true,
    );
    final includeLocalOnly =
        backupPreferenceService.hasSelectedAllFoldersForBackup ||
        isLocalGalleryMode;
    final FileLoadResult result;
    if (includeLocalOnly) {
      result = await FilesDB.instance.getAllLocalAndUploadedFiles(
        startMicros,
        endMicros,
        ownerID,
        filterOptions: filterOptions,
      );
    } else {
      result = await FilesDB.instance.getAllPendingOrUploadedFiles(
        startMicros,
        endMicros,
        ownerID,
        filterOptions: filterOptions,
      );
    }
    _logger.info(
      "Loaded ${result.files.length} files for review in [$startMicros, $endMicros]",
    );
    return result.files;
  }

  Future<void> _reconcileDecisions(
    List<EnteFile> files,
    ReviewDecisionIndex index,
  ) async {
    final updated = <ReviewDecisionRecord>[];
    final stale = <String>[];
    for (final file in files) {
      final record = index.lookup(file);
      final creationTime = file.creationTime;
      if (record == null || creationTime == null) continue;
      final key = fileKey(file);
      final monthKey = ReviewMonthKey.fromCreationTime(creationTime).key;
      if (record.fileKey == key && record.monthKey == monthKey) continue;
      updated.add(
        ReviewDecisionRecord(
          fileKey: key,
          uploadedFileID: file.uploadedFileID,
          localID: file.localID,
          monthKey: monthKey,
          decision: record.decision,
          updatedAt: record.updatedAt,
        ),
      );
      if (record.fileKey != key) stale.add(record.fileKey);
    }
    if (updated.isEmpty) return;
    await _db.rekeyDecisions(updated, stale);
    stale.forEach(index.remove);
    updated.forEach(index.add);
  }

  void _notifyUpdated() {
    Bus.instance.fire(PhotoReviewUpdatedEvent());
  }

  ReviewDecisionRecord _recordFor(
    EnteFile file,
    ReviewMonthKey month,
    ReviewDecision decision,
    int updatedAt,
  ) {
    return ReviewDecisionRecord(
      fileKey: fileKey(file),
      uploadedFileID: file.uploadedFileID,
      localID: file.localID,
      monthKey: month.key,
      decision: decision,
      updatedAt: updatedAt,
    );
  }

  static int _now() => DateTime.now().microsecondsSinceEpoch;
}

class ReviewDecisionIndex {
  ReviewDecisionIndex(List<ReviewDecisionRecord> records) {
    records.forEach(add);
  }

  final Map<String, ReviewDecisionRecord> _byFileKey = {};
  final Map<String, ReviewDecisionRecord> _byLocalID = {};

  Iterable<ReviewDecisionRecord> get records => _byFileKey.values;

  void add(ReviewDecisionRecord record) {
    _byFileKey[record.fileKey] = record;
    final localID = record.localID;
    if (localID != null) {
      _byLocalID[localID] = record;
    }
  }

  void remove(String fileKey) {
    final record = _byFileKey.remove(fileKey);
    final localID = record?.localID;
    if (localID != null && identical(_byLocalID[localID], record)) {
      _byLocalID.remove(localID);
    }
  }

  ReviewDecisionRecord? lookup(EnteFile file) {
    final direct = _byFileKey[PhotoReviewService.fileKey(file)];
    if (direct != null) return direct;
    final localID = file.localID;
    return localID == null ? null : _byLocalID[localID];
  }
}
