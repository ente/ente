import "package:flutter_test/flutter_test.dart";
import "package:photos/services/free_space/deletion_batch_runner.dart";

void main() {
  test("stops after the first platform exception", () async {
    final attemptedBatches = <List<String>>[];

    final result = await executeDeletionBatches(
      localIDs: ["1", "2", "3", "4"],
      batchSize: 2,
      deleteBatch: (ids) async {
        attemptedBatches.add(List.of(ids));
        throw StateError("failed batch");
      },
      checkpoint: (_) async {},
    );

    expect(result.status, LocalDeletionStatus.failed);
    expect(result.shouldTryNextFallback, isTrue);
    expect(attemptedBatches, [
      ["1", "2"],
    ]);
  });

  test("checkpoints an earlier batch before a later failure", () async {
    final attemptedBatches = <List<String>>[];
    final checkpoints = <Set<String>>[];

    final result = await executeDeletionBatches(
      localIDs: ["1", "2", "3", "4", "5"],
      batchSize: 2,
      deleteBatch: (ids) async {
        attemptedBatches.add(List.of(ids));
        if (attemptedBatches.length == 2) {
          throw StateError("failed batch");
        }
        return ids;
      },
      checkpoint: (ids) async => checkpoints.add(Set.of(ids)),
    );

    expect(result.status, LocalDeletionStatus.failed);
    expect(result.deletedIDs, {"1", "2"});
    expect(checkpoints, [
      {"1", "2"},
    ]);
    expect(attemptedBatches, [
      ["1", "2"],
      ["3", "4"],
    ]);
  });

  test("an empty result stops later batches as cancellation", () async {
    final attemptedBatches = <List<String>>[];

    final result = await executeDeletionBatches(
      localIDs: ["1", "2", "3"],
      batchSize: 2,
      deleteBatch: (ids) async {
        attemptedBatches.add(List.of(ids));
        return [];
      },
      checkpoint: (_) async {},
    );

    expect(result.status, LocalDeletionStatus.cancelled);
    expect(attemptedBatches, [
      ["1", "2"],
    ]);
  });

  test("a checkpoint failure prevents another platform batch", () async {
    final attemptedBatches = <List<String>>[];

    final result = await executeDeletionBatches(
      localIDs: ["1", "2", "3"],
      batchSize: 2,
      deleteBatch: (ids) async {
        attemptedBatches.add(List.of(ids));
        return ids;
      },
      checkpoint: (_) async => throw StateError("checkpoint failed"),
    );

    expect(result.status, LocalDeletionStatus.failed);
    expect(result.shouldTryNextFallback, isFalse);
    expect(attemptedBatches, [
      ["1", "2"],
    ]);
  });

  test("preserves legacy Android empty-result completion", () async {
    final attemptedBatches = <List<String>>[];

    final result = await executeDeletionBatches(
      localIDs: ["1", "2", "3", "4", "5"],
      batchSize: 2,
      emptyResultMeansCompleted: true,
      deleteBatch: (ids) async {
        attemptedBatches.add(List.of(ids));
        return [];
      },
      checkpoint: (_) async {},
    );

    expect(result.status, LocalDeletionStatus.completed);
    expect(attemptedBatches.map((ids) => ids.length), [2, 2, 1]);
  });

  test("does not exceed the configured batch size", () async {
    final attemptedBatchSizes = <int>[];
    final ids = List.generate(1901, (index) => "$index");

    final result = await executeDeletionBatches(
      localIDs: ids,
      batchSize: 1900,
      deleteBatch: (ids) async {
        attemptedBatchSizes.add(ids.length);
        return ids;
      },
      checkpoint: (_) async {},
    );

    expect(result.status, LocalDeletionStatus.completed);
    expect(attemptedBatchSizes, [1900, 1]);
  });

  test("completed reconciliation does not hide a platform failure", () {
    final result = combineDeletionResults(
      const LocalDeletionResult(status: LocalDeletionStatus.completed),
      const LocalDeletionResult(
        status: LocalDeletionStatus.failed,
        shouldTryNextFallback: true,
      ),
    );

    expect(result.status, LocalDeletionStatus.failed);
    expect(result.shouldTryNextFallback, isTrue);
  });

  test("retains only originally confirmed, still-freeable candidates", () {
    final candidates = retainOriginalDeletionCandidates(
      refreshedLocalIDs: ["folder-file", "unrelated-file"],
      originalLocalIDs: ["folder-file", "already-handled-file"],
    );

    expect(candidates, {"folder-file"});
  });
}
