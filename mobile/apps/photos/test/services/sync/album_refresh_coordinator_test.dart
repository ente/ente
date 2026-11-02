import "dart:async";

import "package:flutter_test/flutter_test.dart";
import "package:logging/logging.dart";
import "package:photos/services/sync/album_refresh_coordinator.dart";

void main() {
  final records = <LogRecord>[];
  late StreamSubscription<LogRecord> subscription;
  late Level previousLevel;

  setUp(() {
    records.clear();
    previousLevel = Logger.root.level;
    Logger.root.level = Level.ALL;
    subscription = Logger.root.onRecord
        .where((record) => record.loggerName == "AlbumRefreshCoordinator")
        .listen(records.add);
  });

  tearDown(() async {
    await subscription.cancel();
    Logger.root.level = previousLevel;
  });

  test(
    "coalesces bursts and preserves changes during follow-up passes",
    () async {
      final gates = <Completer<bool>>[];
      final observedCounts = <int>[];
      var photoCount = 100;
      var active = 0;
      var maxActive = 0;
      final coordinator = AlbumRefreshCoordinator((_, setStage) async {
        final gate = Completer<bool>();
        gates.add(gate);
        observedCounts.add(photoCount);
        active++;
        if (active > maxActive) maxActive = active;
        try {
          return await gate.future;
        } finally {
          active--;
        }
      });

      final first = coordinator.request();
      await _flush();
      photoCount = 101;
      final burst = List.generate(200, (_) => coordinator.request());
      expect(gates, hasLength(1));
      gates[0].complete(true);
      await _flush();
      expect(gates, hasLength(2));
      expect(await first, isTrue);

      photoCount = 102;
      final laterScan = coordinator.request();
      gates[1].complete(false);
      await _flush();
      expect(gates, hasLength(3));
      expect(await Future.wait(burst), everyElement(isFalse));
      gates[2].complete(true);
      await Future.wait([first, ...burst, laterScan]);

      expect(observedCounts, [100, 101, 102]);
      expect(maxActive, 1);
      expect(records.where((r) => r.level == Level.INFO), hasLength(6));
      expect(records.where((r) => r.level >= Level.WARNING), isEmpty);
    },
  );

  test(
    "runs requested follow-up after failure and releases the guard",
    () async {
      final gates = <Completer<bool>>[];
      final failure = StateError("album lookup failed");
      final coordinator = AlbumRefreshCoordinator((_, setStage) {
        final gate = Completer<bool>();
        gates.add(gate);
        return gate.future;
      });

      final first = coordinator.request();
      final firstError = expectLater(first, throwsA(same(failure)));
      await _flush();
      final joined = coordinator.request();
      gates[0].completeError(failure);
      await _flush();
      expect(gates, hasLength(2));
      gates[1].complete(false);
      await firstError;
      expect(await joined, isFalse);

      final retry = coordinator.request();
      await _flush();
      expect(gates, hasLength(3));
      gates[2].complete(true);
      expect(await retry, isTrue);
      expect(records.where((r) => r.level == Level.SEVERE), hasLength(1));
    },
  );

  test(
    "keeps first-import completion separate from ordinary refreshes",
    () async {
      final gates = <Completer<bool>>[];
      final firstSyncFlags = <bool>[];
      final coordinator = AlbumRefreshCoordinator((isFirstSync, setStage) {
        firstSyncFlags.add(isFirstSync);
        final gate = Completer<bool>();
        gates.add(gate);
        return gate.future;
      });

      final firstImport = coordinator.request(isFirstSync: true);
      final ordinary = coordinator.request();
      await _flush();
      final joined = coordinator.request();
      expect(firstSyncFlags, [true, false]);

      gates[0].complete(true);
      expect(await firstImport, isTrue);
      expect(gates[1].isCompleted, isFalse);
      gates[1].complete(false);
      await _flush();
      expect(firstSyncFlags, [true, false, false]);
      gates[2].complete(false);
      await Future.wait([ordinary, joined]);
    },
  );

  testWidgets(
    "warns once without retrying and cancels completed-pass warnings",
    (tester) async {
      final gates = <Completer<bool>>[];
      final coordinator = AlbumRefreshCoordinator((_, setStage) {
        setStage("reading counts and updating database");
        final gate = Completer<bool>();
        gates.add(gate);
        return gate.future;
      });

      var completed = false;
      final first = coordinator.request();
      unawaited(first.then((_) => completed = true));
      await tester.pump();
      final pending = coordinator.request();
      await tester.pump(const Duration(minutes: 2));
      final warnings = records.where((r) => r.level == Level.WARNING).toList();
      expect(warnings, hasLength(1));
      expect(
        warnings.single.message,
        contains("Album refresh 1 still running"),
      );
      expect(
        warnings.single.message,
        contains("reading counts and updating database"),
      );
      expect(warnings.single.message, contains("pending=true"));
      expect(completed, isFalse);
      expect(gates, hasLength(1));
      await tester.pump(const Duration(minutes: 5));
      expect(records.where((r) => r.level == Level.WARNING), hasLength(1));

      gates[0].complete(false);
      await tester.pump();
      gates[1].complete(false);
      await tester.pump();
      await Future.wait([first, pending]);
      final retry = coordinator.request();
      final retryError = expectLater(retry, throwsStateError);
      await tester.pump();
      gates[2].completeError(StateError("database update failed"));
      await tester.pump();
      await retryError;
      final afterFailure = coordinator.request();
      await tester.pump();
      gates[3].complete(false);
      await tester.pump();
      await afterFailure;
      await tester.pump(const Duration(minutes: 3));
      expect(records.where((r) => r.level == Level.WARNING), hasLength(1));
      expect(records.where((r) => r.level == Level.INFO), hasLength(7));
      expect(records.where((r) => r.level == Level.SEVERE), hasLength(1));
    },
  );
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);
