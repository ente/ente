import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:photos/db/photo_review_db.dart";
import "package:photos/models/photo_review/photo_review_models.dart";

void main() {
  late Directory tempDir;
  late PathProviderPlatform previousPathProvider;

  setUpAll(() async {
    previousPathProvider = PathProviderPlatform.instance;
    tempDir = await Directory.systemTemp.createTemp("photo_review_db_test_");
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDownAll(() async {
    PathProviderPlatform.instance = previousPathProvider;
    await tempDir.delete(recursive: true);
  });

  setUp(() => PhotoReviewDB.instance.clearTable());

  test("stores decisions per month and replaces them by file key", () async {
    final db = PhotoReviewDB.instance;
    await db.saveDecisions(
      [
        _decision("u:1", "2026-01", ReviewDecision.keep),
        _decision("u:2", "2026-01", ReviewDecision.queued, localID: "b"),
      ],
      "2026-01",
      10,
    );
    await db.saveDecisions(
      [_decision("u:3", "2026-02", ReviewDecision.keep)],
      "2026-02",
      11,
    );
    await db.saveDecisions(
      [_decision("u:1", "2026-01", ReviewDecision.deleted)],
      "2026-01",
      12,
    );

    final january = await _forMonth(db, "2026-01");
    expect(january, hasLength(2));
    expect(
      january.singleWhere((record) => record.fileKey == "u:1").decision,
      ReviewDecision.deleted,
    );
    expect(
      january.singleWhere((record) => record.fileKey == "u:2").localID,
      "b",
    );
    expect(await db.getAllDecisions(), hasLength(3));
    expect((await db.getMonthRecord("2026-01"))!.updatedAt, 12);
  });

  test("looks up decisions by file key or local ID across months", () async {
    final db = PhotoReviewDB.instance;
    await db.saveDecisions(
      [
        _decision("u:1", "2026-01", ReviewDecision.keep, localID: "a"),
        _decision("l:b", "2026-01", ReviewDecision.queued, localID: "b"),
      ],
      "2026-01",
      10,
    );
    await db.saveDecisions(
      [_decision("u:3", "2026-02", ReviewDecision.keep)],
      "2026-02",
      11,
    );

    final records = await db.getDecisionsForFiles(["u:3", "u:9"], ["b"]);
    expect(records.map((record) => record.fileKey).toSet(), {"u:3", "l:b"});
    expect(await db.getDecisionsForFiles([], []), isEmpty);
  });

  test("deleting a decision also removes rows matched by local ID", () async {
    final db = PhotoReviewDB.instance;
    await db.saveDecisions(
      [
        _decision("u:1", "2026-01", ReviewDecision.keep, localID: "a"),
        _decision("l:a", "2026-01", ReviewDecision.queued, localID: "a"),
        _decision("u:2", "2026-01", ReviewDecision.keep, localID: "b"),
      ],
      "2026-01",
      10,
    );

    await db.deleteDecision("l:a", "a", "2026-01", 20);

    final remaining = await _forMonth(db, "2026-01");
    expect(remaining.map((record) => record.fileKey), ["u:2"]);
    expect((await db.getMonthRecord("2026-01"))!.updatedAt, 20);

    await db.deleteDecision("u:2", null, "2026-01", 30);
    expect(await _forMonth(db, "2026-01"), isEmpty);
  });

  test(
    "accumulates freed stats and keeps them when marking reviewed",
    () async {
      final db = PhotoReviewDB.instance;
      await db.recordDeletion(
        [_decision("u:1", "2026-01", ReviewDecision.deleted)],
        "2026-01",
        100,
        10,
      );
      await db.recordDeletion(
        [
          _decision("u:2", "2026-01", ReviewDecision.deleted),
          _decision("u:3", "2026-01", ReviewDecision.deleted),
        ],
        "2026-01",
        250,
        11,
      );

      var record = (await db.getMonthRecord("2026-01"))!;
      expect(record.freedBytes, 350);
      expect(record.freedCount, 3);
      expect(record.markedReviewed, isFalse);

      await db.markMonthsReviewed(["2026-01", "2026-02"], 12);

      record = (await db.getMonthRecord("2026-01"))!;
      expect(record.freedBytes, 350);
      expect(record.freedCount, 3);
      expect(record.markedReviewed, isTrue);
      expect(record.updatedAt, 12);
      final february = (await db.getMonthRecord("2026-02"))!;
      expect(february.markedReviewed, isTrue);
      expect(february.freedCount, 0);

      await db.unmarkMonthReviewed("2026-01", 13);

      record = (await db.getMonthRecord("2026-01"))!;
      expect(record.markedReviewed, isFalse);
      expect(record.freedCount, 3);
      expect(record.updatedAt, 13);
    },
  );

  test("rekeying moves decisions to a new key or month unchanged", () async {
    final db = PhotoReviewDB.instance;
    await db.saveDecisions(
      [
        _decision("l:a", "2026-01", ReviewDecision.queued, localID: "a"),
        _decision("u:8", "2026-01", ReviewDecision.keep),
      ],
      "2026-01",
      10,
    );

    await db.rekeyDecisions(
      [
        _decision("u:7", "2026-01", ReviewDecision.queued, localID: "a"),
        _decision("u:8", "2026-02", ReviewDecision.keep),
      ],
      ["l:a"],
    );

    final january = await _forMonth(db, "2026-01");
    expect(january.map((record) => record.fileKey), ["u:7"]);
    expect(january.single.decision, ReviewDecision.queued);
    expect(january.single.updatedAt, 1);
    final february = await _forMonth(db, "2026-02");
    expect(february.map((record) => record.fileKey), ["u:8"]);
    expect(await db.getAllDecisions(), hasLength(2));
    expect((await db.getMonthRecord("2026-01"))!.updatedAt, 10);
    expect(await db.getMonthRecord("2026-02"), isNull);
  });

  test("resetting a month clears its decisions and month record", () async {
    final db = PhotoReviewDB.instance;
    await db.saveDecisions(
      [_decision("u:1", "2026-01", ReviewDecision.keep)],
      "2026-01",
      5,
    );
    await db.saveDecisions(
      [_decision("u:2", "2026-02", ReviewDecision.keep)],
      "2026-02",
      6,
    );
    await db.markMonthsReviewed(["2026-01", "2026-02"], 7);

    await db.resetMonths(["2026-01"]);

    expect(await _forMonth(db, "2026-01"), isEmpty);
    expect(await db.getMonthRecord("2026-01"), isNull);
    expect(await _forMonth(db, "2026-02"), hasLength(1));
    expect((await db.getMonthRecords()).keys, ["2026-02"]);
  });
}

Future<List<ReviewDecisionRecord>> _forMonth(
  PhotoReviewDB db,
  String monthKey,
) async {
  final records = await db.getAllDecisions();
  return records.where((record) => record.monthKey == monthKey).toList();
}

ReviewDecisionRecord _decision(
  String fileKey,
  String monthKey,
  ReviewDecision decision, {
  String? localID,
}) {
  return ReviewDecisionRecord(
    fileKey: fileKey,
    uploadedFileID: int.tryParse(fileKey.substring(2)),
    localID: localID,
    monthKey: monthKey,
    decision: decision,
    updatedAt: 1,
  );
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.documentsPath);

  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}
