import "dart:async";
import "dart:typed_data";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/models/ml/face/box.dart";
import "package:photos/utils/face/face_crop_request_queue.dart";

const _box = FaceBox(x: 0, y: 0, width: 0.5, height: 0.5);

void main() {
  test(
    "queued callers all receive their crops from one merged batch",
    () async {
      final queue = FaceCropRequestQueue(maxConcurrentTasks: 1);
      final gate = Completer<Map<String, Uint8List>?>();
      final blocker = queue.getCrops("blocker", {
        "blocker": _box,
      }, (_) => gate.future);
      final generated = <Set<String>>[];
      final a = Uint8List.fromList([1]);
      final b = Uint8List.fromList([2]);
      Future<Map<String, Uint8List>> generate(
        Map<String, FaceBox> boxes,
      ) async {
        generated.add(boxes.keys.toSet());
        return {"a": a, "b": b};
      }

      final first = queue.getCrops("file-full", {"a": _box}, generate);
      final duplicate = queue.getCrops("file-full", {"a": _box}, generate);
      final otherFace = queue.getCrops("file-full", {"b": _box}, generate);
      gate.complete(null);
      await blocker;
      final results = await Future.wait([first, duplicate, otherFace]);

      expect(generated, [
        {"a", "b"},
      ]);
      expect(results[0]!.keys, ["a"]);
      expect(results[1]!["a"], same(a));
      expect(results[2]!.keys, ["b"]);
      expect(results[2]!["b"], same(b));
    },
    timeout: const Timeout(Duration(seconds: 5)),
  );

  test(
    "running duplicates share results and additional faces run afterward",
    () async {
      final queue = FaceCropRequestQueue(maxConcurrentTasks: 5);
      final gate = Completer<Map<String, Uint8List>?>();
      final a = Uint8List.fromList([1]);
      final b = Uint8List.fromList([2]);
      final batches = <Set<String>>[];
      var active = 0;
      var peakActive = 0;
      Future<Map<String, Uint8List>?> generate(
        Map<String, FaceBox> boxes,
      ) async {
        active++;
        if (active > peakActive) peakActive = active;
        batches.add(boxes.keys.toSet());
        try {
          return batches.length == 1 ? await gate.future : {"b": b};
        } finally {
          active--;
        }
      }

      final first = queue.getCrops("file-full", {"a": _box}, generate);
      final duplicate = queue.getCrops("file-full", {"a": _box}, generate);
      final extra = queue.getCrops("file-full", {
        "a": _box,
        "b": _box,
      }, generate);
      expect(batches, [
        {"a"},
      ]);
      gate.complete({"a": a});
      final results = await Future.wait([first, duplicate, extra]);

      expect(peakActive, 1);
      expect(batches, [
        {"a"},
        {"b"},
      ]);
      expect(results[0]!["a"], same(a));
      expect(results[1]!["a"], same(a));
      expect(results[2]!.keys, ["a", "b"]);
      expect(results[2]!["b"], same(b));
    },
  );

  test(
    "an error reaches all callers and does not poison the next request",
    () async {
      final queue = FaceCropRequestQueue();
      final gate = Completer<Map<String, Uint8List>?>();
      final error = StateError("crop failed");
      var calls = 0;
      Future<Map<String, Uint8List>?> generate(Map<String, FaceBox> _) {
        calls++;
        return gate.future;
      }

      final first = queue.getCrops("file-full", {"a": _box}, generate);
      final duplicate = queue.getCrops("file-full", {"a": _box}, generate);
      final firstError = expectLater(first, throwsA(same(error)));
      final secondError = expectLater(duplicate, throwsA(same(error)));
      gate.completeError(error);
      await Future.wait([firstError, secondError]);
      expect(calls, 1);

      final bytes = Uint8List.fromList([3]);
      final retry = await queue.getCrops("file-full", {
        "a": _box,
      }, (_) async => {"a": bytes});
      expect(retry!["a"], same(bytes));
    },
  );

  test(
    "an immediate replacement after overflow does not join the failed batch",
    () async {
      final queue = FaceCropRequestQueue(
        maxConcurrentTasks: 1,
        maxQueueSize: 1,
      );
      final gate = Completer<Map<String, Uint8List>?>();
      final blocker = queue.getCrops("blocker", {
        "blocker": _box,
      }, (_) => gate.future);
      var discardedCalls = 0;
      Future<Map<String, Uint8List>?> discardedGenerate(
        Map<String, FaceBox> _,
      ) async {
        discardedCalls++;
        return null;
      }

      final original = queue.getCrops("file-full", {
        "old": _box,
      }, discardedGenerate);
      final originalFailure = expectLater(
        original,
        throwsA(isA<TaskQueueOverflowException>()),
      );
      final intervening = queue.getCrops("other-file", {
        "other": _box,
      }, discardedGenerate);
      final interveningFailure = expectLater(
        intervening,
        throwsA(isA<TaskQueueOverflowException>()),
      );

      // Overflow has synchronously removed the original queue item, but its
      // asynchronous failure callback has not removed the wrapper batch yet.
      final bytes = Uint8List.fromList([5]);
      final replacement = queue.getCrops("file-full", {
        "fresh": _box,
      }, (_) async => {"fresh": bytes});
      final replacementResult = expectLater(
        replacement,
        completion({"fresh": bytes}),
      );
      gate.complete(null);
      await Future.wait([
        blocker,
        originalFailure,
        interveningFailure,
        replacementResult,
      ]);
      expect(discardedCalls, 0);
    },
  );

  test(
    "one canceled queued consumer leaves the other consumer's work intact",
    () async {
      final queue = FaceCropRequestQueue(maxConcurrentTasks: 1);
      final gate = Completer<Map<String, Uint8List>?>();
      final blocker = queue.getCrops("blocker", {
        "blocker": _box,
      }, (_) => gate.future);
      final bytes = Uint8List.fromList([1]);
      var calls = 0;
      Future<Map<String, Uint8List>> generate(Map<String, FaceBox> _) async {
        calls++;
        return {"a": bytes};
      }

      final first = queue.getCrops("file-full", {"a": _box}, generate);
      final duplicate = queue.getCrops("file-full", {"a": _box}, generate);
      queue.removeTask("file-full");
      gate.complete(null);
      await blocker;
      final results = await Future.wait([first, duplicate]);
      expect(calls, 1);
      expect(results[1]!["a"], same(bytes));
    },
  );

  test(
    "canceling all queued consumers fails their requests and permits a replacement",
    () async {
      final queue = FaceCropRequestQueue(maxConcurrentTasks: 1);
      final gate = Completer<Map<String, Uint8List>?>();
      final blocker = queue.getCrops("blocker", {
        "blocker": _box,
      }, (_) => gate.future);
      var canceledCalls = 0;
      Future<Map<String, Uint8List>?> canceledGenerate(
        Map<String, FaceBox> _,
      ) async {
        canceledCalls++;
        return null;
      }

      final first = queue.getCrops("file-full", {"a": _box}, canceledGenerate);
      final duplicate = queue.getCrops("file-full", {
        "a": _box,
      }, canceledGenerate);
      final firstError = expectLater(
        first,
        throwsA(isA<TaskQueueCancelledException>()),
      );
      final secondError = expectLater(
        duplicate,
        throwsA(isA<TaskQueueCancelledException>()),
      );
      queue.removeTask("file-full");
      queue.removeTask("file-full");
      final bytes = Uint8List.fromList([4]);
      final replacement = queue.getCrops("file-full", {
        "a": _box,
      }, (_) async => {"a": bytes});
      gate.complete(null);
      await Future.wait([blocker, firstError, secondError]);
      expect((await replacement)!["a"], same(bytes));
      expect(canceledCalls, 0);
    },
  );
}
