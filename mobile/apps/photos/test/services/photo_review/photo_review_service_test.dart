import "package:flutter_test/flutter_test.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/photo_review/photo_review_models.dart";
import "package:photos/services/photo_review/photo_review_service.dart";

void main() {
  group("ReviewMonthKey", () {
    test("round-trips through its string key", () {
      const key = ReviewMonthKey(2026, 1);
      expect(key.key, "2026-01");
      expect(ReviewMonthKey.fromCreationTime(key.startMicros), key);
      expect(ReviewMonthKey.fromCreationTime(key.endMicros), key);
      expect(
        ReviewMonthKey.fromCreationTime(key.endMicros + 1),
        const ReviewMonthKey(2026, 2),
      );
    });
  });

  group("ReviewDecisionIndex", () {
    test("matches by file key, then by local ID", () {
      final index = ReviewDecisionIndex([
        _record("u:10", uploadedFileID: 10, localID: "a"),
        _record("l:b", localID: "b", decision: ReviewDecision.queued),
      ]);

      expect(index.lookup(_file(uploadedFileID: 10))?.fileKey, "u:10");
      expect(
        index.lookup(_file(uploadedFileID: 99, localID: "b"))?.decision,
        ReviewDecision.queued,
      );
      expect(index.lookup(_file(localID: "a"))?.fileKey, "u:10");
      expect(index.lookup(_file(uploadedFileID: 11, localID: "c")), isNull);
    });
  });

  group("PhotoReviewService.buildOverview", () {
    test("groups months by year and derives state from decisions", () {
      const december = ReviewMonthKey(2025, 12);
      const january = ReviewMonthKey(2026, 1);
      const february = ReviewMonthKey(2026, 2);
      final overview = PhotoReviewService.buildOverview(
        [
          _file(uploadedFileID: 1, month: january),
          _file(uploadedFileID: 2, month: january),
          _file(uploadedFileID: 3, month: january),
          _file(uploadedFileID: 4, month: february),
          _file(uploadedFileID: 5, month: december),
        ],
        [
          _record("u:1", uploadedFileID: 1, month: january),
          _record(
            "u:2",
            uploadedFileID: 2,
            month: january,
            decision: ReviewDecision.queued,
          ),
          _record(
            "u:4",
            uploadedFileID: 4,
            month: february,
            decision: ReviewDecision.deleted,
          ),
        ],
        const {},
      );

      expect(overview.years.map((year) => year.year), [2026, 2025]);
      expect(overview.years.first.months.map((month) => month.key), [
        january,
        february,
      ]);
      final months = {for (final month in overview.months) month.key: month};
      expect(months[january]!.state, ReviewMonthState.inProgress);
      expect(months[january]!.decidedCount, 2);
      expect(months[january]!.queuedCount, 1);
      expect(months[january]!.progressPercent, 66);
      expect(months[february]!.state, ReviewMonthState.normal);
      expect(months[december]!.state, ReviewMonthState.normal);
      expect(overview.bannerMonths.map((m) => m.key), [january, february]);
    });

    test("marks a month completed when flagged, even with new files", () {
      const january = ReviewMonthKey(2026, 1);
      final overview = PhotoReviewService.buildOverview(
        [_file(uploadedFileID: 1, month: january)],
        const [],
        {
          january.key: ReviewMonthRecord(
            monthKey: january.key,
            markedReviewed: true,
            freedBytes: 0,
            freedCount: 0,
            updatedAt: 1,
          ),
        },
      );

      expect(overview.months.single.state, ReviewMonthState.completed);
      expect(overview.years.single.isCompleted, isTrue);
      expect(overview.bannerMonths, isEmpty);
    });

    test("banner lists months in progress, most recently touched first", () {
      const january = ReviewMonthKey(2026, 1);
      const march = ReviewMonthKey(2026, 3);
      final overview = PhotoReviewService.buildOverview(
        [
          _file(uploadedFileID: 1, month: january),
          _file(uploadedFileID: 2, month: january),
          _file(uploadedFileID: 3, month: march),
          _file(uploadedFileID: 4, month: march),
        ],
        [
          _record("u:1", uploadedFileID: 1, month: january),
          _record("u:3", uploadedFileID: 3, month: march),
        ],
        {
          january.key: ReviewMonthRecord(
            monthKey: january.key,
            markedReviewed: false,
            freedBytes: 0,
            freedCount: 0,
            updatedAt: 200,
          ),
          march.key: ReviewMonthRecord(
            monthKey: march.key,
            markedReviewed: false,
            freedBytes: 0,
            freedCount: 0,
            updatedAt: 100,
          ),
        },
      );

      expect(overview.bannerMonths.map((m) => m.key), [january, march]);
    });
  });

  group("PhotoReviewService.nextMonthToReview", () {
    test("moves to the next older unfinished month, then wraps", () {
      const may = ReviewMonthKey(2026, 5);
      const april = ReviewMonthKey(2026, 4);
      const march = ReviewMonthKey(2026, 3);
      const june = ReviewMonthKey(2026, 6);
      final overview = PhotoReviewService.buildOverview(
        [
          _file(uploadedFileID: 1, month: june),
          _file(uploadedFileID: 2, month: may),
          _file(uploadedFileID: 3, month: april),
          _file(uploadedFileID: 4, month: march),
        ],
        [_record("u:3", uploadedFileID: 3, month: april)],
        const {},
      );

      expect(PhotoReviewService.nextMonthToReview(overview, may), march);
      expect(PhotoReviewService.nextMonthToReview(overview, march), june);
      expect(
        PhotoReviewService.nextMonthToReview(
          PhotoReviewService.buildOverview(
            [_file(uploadedFileID: 1, month: may)],
            [_record("u:1", uploadedFileID: 1, month: may)],
            const {},
          ),
          may,
        ),
        isNull,
      );
    });
  });
}

EnteFile _file({
  int? uploadedFileID,
  String? localID,
  ReviewMonthKey month = const ReviewMonthKey(2026, 1),
}) {
  return EnteFile()
    ..generatedID = (uploadedFileID ?? 0) * 100 + (localID?.hashCode ?? 0)
    ..uploadedFileID = uploadedFileID
    ..localID = localID
    ..fileType = FileType.image
    ..creationTime = month.startMicros + 1;
}

ReviewDecisionRecord _record(
  String fileKey, {
  int? uploadedFileID,
  String? localID,
  ReviewMonthKey month = const ReviewMonthKey(2026, 1),
  ReviewDecision decision = ReviewDecision.keep,
}) {
  return ReviewDecisionRecord(
    fileKey: fileKey,
    uploadedFileID: uploadedFileID,
    localID: localID,
    monthKey: month.key,
    decision: decision,
    updatedAt: 1,
  );
}
