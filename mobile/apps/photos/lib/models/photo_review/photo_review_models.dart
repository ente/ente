import "package:photos/models/file/file.dart";

enum ReviewDecision {
  keep(0),
  queued(1),
  deleted(2);

  const ReviewDecision(this.storedValue);

  final int storedValue;

  static ReviewDecision fromStoredValue(int value) {
    return ReviewDecision.values.firstWhere(
      (decision) => decision.storedValue == value,
    );
  }
}

enum ReviewMonthState { normal, inProgress, completed }

class ReviewMonthKey implements Comparable<ReviewMonthKey> {
  const ReviewMonthKey(this.year, this.month);

  factory ReviewMonthKey.fromCreationTime(int creationTimeMicros) {
    final date = DateTime.fromMicrosecondsSinceEpoch(creationTimeMicros);
    return ReviewMonthKey(date.year, date.month);
  }

  final int year;
  final int month;

  String get key => "$year-${month.toString().padLeft(2, "0")}";

  DateTime get start => DateTime(year, month);

  int get startMicros => start.microsecondsSinceEpoch;

  int get endMicros => DateTime(year, month + 1).microsecondsSinceEpoch - 1;

  @override
  int compareTo(ReviewMonthKey other) {
    if (year != other.year) return year.compareTo(other.year);
    return month.compareTo(other.month);
  }

  @override
  bool operator ==(Object other) =>
      other is ReviewMonthKey && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);

  @override
  String toString() => key;
}

class ReviewDecisionRecord {
  const ReviewDecisionRecord({
    required this.fileKey,
    required this.uploadedFileID,
    required this.localID,
    required this.monthKey,
    required this.decision,
    required this.updatedAt,
  });

  final String fileKey;
  final int? uploadedFileID;
  final String? localID;
  final String monthKey;
  final ReviewDecision decision;
  final int updatedAt;
}

class ReviewMonthRecord {
  const ReviewMonthRecord({
    required this.monthKey,
    required this.markedReviewed,
    required this.freedBytes,
    required this.freedCount,
    required this.updatedAt,
  });

  final String monthKey;
  final bool markedReviewed;
  final int freedBytes;
  final int freedCount;
  final int updatedAt;

  ReviewMonthRecord copyWith({required bool markedReviewed}) {
    return ReviewMonthRecord(
      monthKey: monthKey,
      markedReviewed: markedReviewed,
      freedBytes: freedBytes,
      freedCount: freedCount,
      updatedAt: updatedAt,
    );
  }
}

class ReviewMonthSummary {
  const ReviewMonthSummary({
    required this.key,
    required this.cover,
    required this.totalCount,
    required this.decidedCount,
    required this.queuedCount,
    required this.markedReviewed,
    required this.lastReviewedAt,
  });

  final ReviewMonthKey key;
  final EnteFile cover;
  final int totalCount;
  final int decidedCount;
  final int queuedCount;
  final bool markedReviewed;
  final int lastReviewedAt;

  bool get isCompleted =>
      markedReviewed || (totalCount > 0 && decidedCount >= totalCount);

  ReviewMonthState get state {
    if (isCompleted) return ReviewMonthState.completed;
    if (decidedCount > 0) return ReviewMonthState.inProgress;
    return ReviewMonthState.normal;
  }

  bool get hasProgress => markedReviewed || decidedCount > 0;

  double get progress =>
      totalCount == 0 ? 0 : (decidedCount / totalCount).clamp(0, 1);

  int get progressPercent => (progress * 100).floor();
}

class ReviewYearSummary {
  const ReviewYearSummary({required this.year, required this.months});

  final int year;
  final List<ReviewMonthSummary> months;

  bool get isCompleted => months.every((month) => month.isCompleted);
}

class ReviewOverview {
  const ReviewOverview({required this.years, required this.bannerMonths});

  final List<ReviewYearSummary> years;
  final List<ReviewMonthSummary> bannerMonths;

  bool get isEmpty => years.isEmpty;

  Iterable<ReviewMonthSummary> get months =>
      years.expand((year) => year.months);
}

class ReviewMonthData {
  const ReviewMonthData({
    required this.files,
    required this.decisions,
    required this.history,
    required this.record,
  });

  final List<EnteFile> files;
  final Map<String, ReviewDecision> decisions;
  final List<(EnteFile, ReviewDecision)> history;
  final ReviewMonthRecord? record;
}
