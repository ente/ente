import "dart:async";
import "dart:ui";

import "package:flutter/services.dart";
import "package:flutter/widgets.dart";

enum BackgroundTaskKind { refresh, processing }

enum BackgroundStopReason { foreground, budget, requested, preempted, system }

enum BackgroundTaskResult { completed, skipped, stopped, failed }

enum BackgroundOutcome { skipped, stopped, failed, forcedTeardown }

class BackgroundTaskConfig {
  const BackgroundTaskConfig({
    required this.identifier,
    required this.kind,
    required this.frequency,
    this.initialDelay = Duration.zero,
    this.flexInterval,
    this.requiresNetwork = false,
    this.requiresCharging = false,
    this.requiresDeviceIdle = false,
    this.runBudget,
    this.foregroundStopTimeout,
  });

  final String identifier;
  final BackgroundTaskKind kind;
  final Duration frequency;
  final Duration initialDelay;
  final Duration? flexInterval;
  final bool requiresNetwork;
  final bool requiresCharging;
  final bool requiresDeviceIdle;
  final Duration? runBudget;
  final Duration? foregroundStopTimeout;

  Map<String, Object> _encode() {
    if (identifier.isEmpty || frequency <= Duration.zero) {
      throw ArgumentError("A task needs an identifier and positive frequency");
    }
    for (final duration in [
      initialDelay,
      flexInterval,
      runBudget,
      foregroundStopTimeout,
    ]) {
      if (duration != null && duration.isNegative) {
        throw ArgumentError("Task durations cannot be negative");
      }
    }
    return {
      "identifier": identifier,
      "kind": kind.name,
      "frequencyMs": frequency.inMilliseconds,
      "initialDelayMs": initialDelay.inMilliseconds,
      "requiresNetwork": requiresNetwork,
      "requiresCharging": requiresCharging,
      "requiresDeviceIdle": requiresDeviceIdle,
      if (flexInterval != null) "flexMs": flexInterval!.inMilliseconds,
      if (runBudget != null) "runBudgetMs": runBudget!.inMilliseconds,
      if (foregroundStopTimeout != null)
        "foregroundStopTimeoutMs": foregroundStopTimeout!.inMilliseconds,
    };
  }
}

class BackgroundTask {
  BackgroundTask._(Map<Object?, Object?> data)
    : identifier = data["identifier"]! as String,
      _invocation = data["invocation"]! as String,
      _startupElapsed = Duration(milliseconds: data["elapsedMs"]! as int),
      runBudget = data["runBudgetMs"] == null
          ? null
          : Duration(milliseconds: data["runBudgetMs"]! as int) {
    final reason = data["stopReason"] as String?;
    if (reason != null) _stop(reason);
  }

  final String identifier;
  final Duration? runBudget;
  final String _invocation;
  final Duration _startupElapsed;
  final Stopwatch _clock = Stopwatch()..start();
  final Completer<BackgroundStopReason> _stopped = Completer();
  BackgroundStopReason? _stopReason;

  Duration get elapsed => _startupElapsed + _clock.elapsed;
  Duration? get remainingBudget {
    final budget = runBudget;
    if (budget == null) return null;
    final remaining = budget - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool get isStopping => _stopReason != null;
  BackgroundStopReason? get stopReason => _stopReason;
  Future<BackgroundStopReason> get stopped => _stopped.future;

  void throwIfStopping() {
    if (isStopping) throw const BackgroundTaskStopped();
  }

  void _stop(String reason) {
    if (isStopping) return;
    _stopReason = BackgroundStopReason.values.byName(reason);
    _stopped.complete(_stopReason);
  }
}

class BackgroundTaskStopped implements Exception {
  const BackgroundTaskStopped();
}

class BackgroundTaskOutcome {
  BackgroundTaskOutcome._(Map<Object?, Object?> data)
    : identifier = data["identifier"]! as String,
      outcome = BackgroundOutcome.values.byName(data["outcome"]! as String),
      reason = data["reason"] as String?,
      error = data["error"] as String?;

  final String identifier;
  final BackgroundOutcome outcome;
  final String? reason;
  final String? error;
}

class BackgroundManager {
  static const _control = MethodChannel("io.ente.background/control");
  static const _worker = MethodChannel("io.ente.background/worker");

  static Future<void> configure({
    required void Function() dispatcher,
    required List<BackgroundTaskConfig> tasks,
    required bool enabled,
    required FutureOr<void> Function(BackgroundTaskOutcome) onOutcome,
  }) async {
    final callback = PluginUtilities.getCallbackHandle(dispatcher);
    if (callback == null) {
      throw ArgumentError(
        "The dispatcher must be a retained top-level function",
      );
    }
    final identifiers = tasks.map((task) => task.identifier).toSet();
    if (identifiers.length != tasks.length) {
      throw ArgumentError("Task identifiers must be unique");
    }
    final encoded = tasks.map((task) => task._encode()).toList();
    _control.setMethodCallHandler((call) async {
      if (call.method != "outcome") throw MissingPluginException();
      await onOutcome(
        BackgroundTaskOutcome._(call.arguments as Map<Object?, Object?>),
      );
      return true;
    });
    await _control.invokeMethod<void>("configure", {
      "callbackHandle": callback.toRawHandle(),
      "tasks": encoded,
      "enabled": enabled,
    });
  }

  static Future<void> stopActiveRun() =>
      _control.invokeMethod<void>("stopActiveRun");

  static Future<Map<String, bool>> scheduledTasks() async {
    final result = await _control.invokeMapMethod<String, bool>(
      "scheduledTasks",
    );
    return result ?? {};
  }

  static Future<void> executeTask(
    Future<BackgroundTaskResult> Function(BackgroundTask) executor,
  ) async {
    WidgetsFlutterBinding.ensureInitialized();
    BackgroundTask? task;
    final pendingStops = <String, String>{};
    _worker.setMethodCallHandler((call) async {
      if (call.method != "stop") throw MissingPluginException();
      final data = call.arguments as Map<Object?, Object?>;
      final invocation = data["invocation"]! as String;
      final reason = data["reason"]! as String;
      final current = task;
      if (current == null) {
        pendingStops.putIfAbsent(invocation, () => reason);
      } else if (current._invocation == invocation) {
        current._stop(reason);
      }
    });
    final data = await _worker.invokeMapMethod<Object?, Object?>("ready");
    if (data == null) return;
    final current = BackgroundTask._(data);
    task = current;
    final pendingStop = pendingStops[current._invocation];
    if (pendingStop != null) current._stop(pendingStop);
    pendingStops.clear();
    var result = BackgroundTaskResult.stopped;
    String? error;
    try {
      current.throwIfStopping();
      result = await executor(current);
    } on BackgroundTaskStopped {
      result = BackgroundTaskResult.stopped;
    } catch (exception) {
      result = BackgroundTaskResult.failed;
      error = exception.runtimeType.toString();
    }
    await _worker.invokeMethod<void>("complete", {
      "invocation": current._invocation,
      "outcome": result.name,
      "error": ?error,
    });
  }
}
