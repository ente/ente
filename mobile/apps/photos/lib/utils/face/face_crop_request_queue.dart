import "dart:async";
import "dart:typed_data";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:photos/models/ml/face/box.dart";

typedef FaceCropGenerator =
    Future<Map<String, Uint8List>?> Function(Map<String, FaceBox> faceBoxes);

// Shares the crop result as well as the queue slot. TaskQueue only shares its
// Future<void>, so a separate result completer for each caller can strand
// callers whose duplicate task callback never runs.
class FaceCropRequestQueue {
  final TaskQueue<String> _queue;
  final Map<String, _FaceCropBatch> _batches = {};

  FaceCropRequestQueue({
    int maxConcurrentTasks = 5,
    Duration taskTimeout = const Duration(minutes: 1),
    int maxQueueSize = 100,
  }) : _queue = TaskQueue<String>(
         maxConcurrentTasks: maxConcurrentTasks,
         taskTimeout: taskTimeout,
         maxQueueSize: maxQueueSize,
       );

  Future<Map<String, Uint8List>?> getCrops(
    String taskId,
    Map<String, FaceBox> faceBoxes,
    FaceCropGenerator generate,
  ) async {
    final remaining = Map<String, FaceBox>.of(faceBoxes);
    final result = <String, Uint8List>{};
    while (remaining.isNotEmpty) {
      var batch = _batches[taskId];
      if (batch == null || !batch.started) {
        final previousBatch = batch;
        final currentBatch = _FaceCropBatch(remaining);
        _batches[taskId] = currentBatch;
        final queued = _queue.addTask(taskId, () async {
          currentBatch.started = true;
          currentBatch.result = await generate(
            Map<String, FaceBox>.unmodifiable(currentBatch.faceBoxes),
          );
        });
        if (previousBatch != null && identical(queued, previousBatch.queued)) {
          // Joining an existing pending task also refreshes its queue priority
          // and adds the consumer's cancellation reference.
          batch = previousBatch;
          batch.faceBoxes.addAll(remaining);
          _batches[taskId] = batch;
        } else {
          // Overflow or timeout can remove a task before its failure callback
          // clears our batch. A different queue future belongs to a new task.
          batch = currentBatch;
          currentBatch.queued = queued;
          unawaited(
            queued.then(
              (_) {
                _removeBatch(taskId, currentBatch);
                currentBatch.completer.complete(currentBatch.result);
              },
              onError: (Object error, StackTrace stack) {
                _removeBatch(taskId, currentBatch);
                currentBatch.completer.completeError(error, stack);
              },
            ),
          );
        }
      }

      final crops = await batch.completer.future;
      for (final faceId in remaining.keys) {
        final crop = crops?[faceId];
        if (crop != null) result[faceId] = crop;
      }
      // A running batch cannot take more boxes. Request any additional faces
      // in a subsequent batch, without generating this file concurrently.
      // Missing results for attempted faces are left missing, not retried here.
      remaining.removeWhere(
        (faceId, _) => batch!.faceBoxes.containsKey(faceId),
      );
    }
    return result.isEmpty ? null : result;
  }

  void removeTask(String taskId) {
    final batch = _batches[taskId];
    if (_queue.removeTask(taskId) && batch != null) {
      _removeBatch(taskId, batch);
    }
  }

  void _removeBatch(String taskId, _FaceCropBatch batch) {
    if (identical(_batches[taskId], batch)) {
      _batches.remove(taskId);
    }
  }
}

class _FaceCropBatch {
  final Map<String, FaceBox> faceBoxes;
  final completer = Completer<Map<String, Uint8List>?>();
  late final Future<void> queued;
  bool started = false;
  Map<String, Uint8List>? result;

  _FaceCropBatch(Map<String, FaceBox> boxes)
    : faceBoxes = Map<String, FaceBox>.of(boxes);
}
