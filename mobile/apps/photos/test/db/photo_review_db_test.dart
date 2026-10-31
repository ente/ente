import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:photos/db/photo_review_db.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/photo_review/photo_review_models.dart";
import "package:photos/services/photo_review/photo_review_service.dart";

void main() {
  final db = PhotoReviewDB.instance;
  const month = "2026-01";
  late Directory tempDir;
  late PathProviderPlatform previousPathProvider;

  setUpAll(() async {
    previousPathProvider = PathProviderPlatform.instance;
    tempDir = await Directory.systemTemp.createTemp("photo_review_db_test_");
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDownAll(() async {
    await (await db.database).close();
    PathProviderPlatform.instance = previousPathProvider;
    await tempDir.delete(recursive: true);
  });

  setUp(db.clearTable);

  test("uploaded copies do not inherit each other's decisions", () {
    final original = _decision("u:7", generatedID: 42);
    final copy = EnteFile()
      ..uploadedFileID = 8
      ..generatedID = 43
      ..localID = "a";
    expect(ReviewDecisionIndex([original]).lookup(copy), isNull);

    final pending = _decision("l:a", generatedID: 43);
    final index = ReviewDecisionIndex([pending, original]);
    expect(index.lookup(copy), same(pending));
    copy.uploadedFileID = 7;
    expect(index.lookup(copy), same(original));
  });

  test("pending decisions only follow their own uploaded file", () {
    final pending = _decision("l:a", generatedID: 42);
    final index = ReviewDecisionIndex([pending]);
    final uploaded = EnteFile()
      ..uploadedFileID = 7
      ..generatedID = 42
      ..localID = "a";
    expect(index.lookup(uploaded), same(pending));
    uploaded.generatedID = 43;
    expect(index.lookup(uploaded), isNull);
    uploaded.generatedID = null;
    expect(index.lookup(uploaded), isNull);
  });

  test("undo removes only the selected upload and its pending alias", () async {
    await db.saveDecisions(
      [
        _decision("l:a", generatedID: 42),
        _decision("u:7", generatedID: 42),
        _decision("u:8", generatedID: 43, decision: ReviewDecision.keep),
      ],
      month,
      10,
    );
    await PhotoReviewService.instance.removeDecision(
      EnteFile()
        ..uploadedFileID = 7
        ..generatedID = 44
        ..localID = "a",
      const ReviewMonthKey(2026, 1),
    );
    expect((await db.getAllDecisions()).single.fileKey, "u:8");

    await db.saveDecisions([_decision("l:a")], month, 30);
    await db.deleteDecision("l:a", month, 40);
    final remaining = (await db.getAllDecisions()).single;
    expect(remaining.fileKey, "u:8");
    expect(remaining.decision, ReviewDecision.keep);
  });

  test("undo of an uploaded copy preserves another pending decision", () async {
    final copy = EnteFile()
      ..uploadedFileID = 8
      ..generatedID = 43
      ..localID = "a";
    await db.saveDecisions(
      [_decision("l:a", generatedID: 42), _decision("u:8", generatedID: 43)],
      month,
      10,
    );
    await PhotoReviewService.instance.removeDecision(
      copy,
      const ReviewMonthKey(2026, 1),
    );
    expect((await db.getAllDecisions()).single.fileKey, "l:a");
  });

  test(
    "undo with a pre-upload file removes its promoted decision only",
    () async {
      final local = EnteFile()
        ..localID = "a"
        ..generatedID = 42;
      await db.saveDecisions(
        [_decision("l:a", generatedID: 42), _decision("u:8", generatedID: 43)],
        month,
        10,
      );
      await db.rekeyDecisions({
        "l:a": _decision("u:7", localID: null, generatedID: 42),
      });

      await PhotoReviewService.instance.removeDecision(
        local,
        const ReviewMonthKey(2026, 1),
      );

      expect((await db.getAllDecisions()).single.fileKey, "u:8");
    },
  );

  test(
    "stale upload reconciliation cannot resurrect an undone decision",
    () async {
      await db.saveDecisions([_decision("l:a")], month, 10);
      final stale = _decision("u:7");
      await db.deleteDecision("l:a", month, 20);

      await db.rekeyDecisions({"l:a": stale});

      expect(await db.getAllDecisions(), isEmpty);
      expect((await db.getMonthRecord(month))!.updatedAt, 20);
    },
  );

  test("reconciliation preserves a newer decision and its timestamp", () async {
    await db.saveDecisions([_decision("l:a")], month, 10);
    final stale = _decision("u:7", month: "2026-02");
    await db.saveDecisions(
      [_decision("l:a", decision: ReviewDecision.keep, updatedAt: 20)],
      month,
      20,
    );

    await db.rekeyDecisions({"l:a": stale});

    final current = (await db.getAllDecisions()).single;
    expect(current.fileKey, "u:7");
    expect(current.monthKey, "2026-02");
    expect(current.decision, ReviewDecision.keep);
    expect(current.updatedAt, 20);
  });

  test("stale reconciliation preserves a different pending file", () async {
    await db.saveDecisions([_decision("l:a", generatedID: 42)], month, 10);
    final stale = _decision("u:7", generatedID: 42);
    await db.saveDecisions([_decision("l:a", generatedID: 43)], month, 20);

    await db.rekeyDecisions({"l:a": stale});

    final current = (await db.getAllDecisions()).single;
    expect(current.fileKey, "l:a");
    expect(current.generatedID, 43);
  });

  test(
    "deletion from a pre-upload snapshot clears its promoted queue",
    () async {
      await db.saveDecisions(
        [_decision("u:7", generatedID: 42), _decision("u:8", generatedID: 43)],
        month,
        10,
      );
      await db.recordDeletion(
        [_decision("l:a", generatedID: 42, decision: ReviewDecision.deleted)],
        month,
        100,
        20,
      );

      final records = await db.getAllDecisions();
      expect(
        records.map((record) => record.fileKey),
        unorderedEquals(["l:a", "u:8"]),
      );
      expect(
        records.firstWhere((record) => record.fileKey == "u:8").decision,
        ReviewDecision.queued,
      );
    },
  );

  test("reconciliation preserves an existing uploaded decision", () async {
    await db.saveDecisions(
      [
        _decision("l:a"),
        _decision("u:7", decision: ReviewDecision.keep, updatedAt: 20),
      ],
      month,
      20,
    );

    await db.rekeyDecisions({"l:a": _decision("u:7")});

    final current = (await db.getAllDecisions()).single;
    expect(current.fileKey, "u:7");
    expect(current.decision, ReviewDecision.keep);
    expect(current.updatedAt, 20);
  });

  test(
    "progress survives upload and loss of the local ID, then undoes",
    () async {
      await db.saveDecisions([_decision("l:a", generatedID: 42)], month, 10);
      final uploaded = EnteFile()
        ..uploadedFileID = 7
        ..generatedID = 42;
      final records = await db.getDecisionsForFiles(
        [PhotoReviewService.fileKey(uploaded)],
        [],
        generatedIDs: [42],
      );
      final matched = ReviewDecisionIndex(records).lookup(uploaded);
      expect(matched?.decision, ReviewDecision.queued);

      await db.rekeyDecisions({
        matched!.fileKey: _decision("u:7", localID: null, generatedID: 42),
      });
      expect((await db.getAllDecisions()).single.fileKey, "u:7");
      await db.deleteDecision("u:7", month, 20, uploadedFileID: 7);
      expect(await db.getAllDecisions(), isEmpty);
    },
  );

  test("resetting one month leaves another month's progress intact", () async {
    await db.saveDecisions(
      [_decision("u:1"), _decision("u:2", month: "2026-02")],
      month,
      10,
    );
    await db.markMonthsReviewed([month, "2026-02"], 20);

    await db.resetMonths([month]);

    expect((await db.getAllDecisions()).single.fileKey, "u:2");
    expect(await db.getMonthRecord(month), isNull);
    expect((await db.getMonthRecord("2026-02"))!.markedReviewed, isTrue);
  });
}

ReviewDecisionRecord _decision(
  String key, {
  ReviewDecision decision = ReviewDecision.queued,
  String month = "2026-01",
  String? localID = "a",
  int? generatedID,
  int updatedAt = 1,
}) => ReviewDecisionRecord(
  fileKey: key,
  uploadedFileID: key.startsWith("u:") ? int.parse(key.substring(2)) : null,
  localID: localID,
  generatedID: generatedID,
  monthKey: month,
  decision: decision,
  updatedAt: updatedAt,
);

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.documentsPath);

  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}
