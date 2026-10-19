import "package:photos/main.dart" show isProcessBg;
import "package:photos/services/machine_learning/ml_process_lock.dart";

const kMlMigrationLockWaitDeadline = Duration(minutes: 2);

Future<void> runMlOperationExclusive(
  MlOperation operation,
  Future<void> Function() body, {
  Duration? waitDeadline,
}) async {
  final attempt = await MlProcessLock.instance.tryRunExclusive(
    operation,
    body,
    background: isProcessBg,
    waitForAvailability: true,
    waitDeadline: waitDeadline,
  );
  if (attempt != MlLockAttempt.ran) {
    throw StateError(
      "${operation.name} could not acquire the ML process lock "
      "(${attempt.name})",
    );
  }
}
