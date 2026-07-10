import 'dart:async';
import 'dart:isolate';

import "package:dart_ui_isolate/dart_ui_isolate.dart";
import "package:flutter/services.dart";
import "package:logging/logging.dart";
import "package:photos/core/error-reporting/isolate_logging.dart";
import "package:photos/core/error-reporting/super_logging.dart";
import "package:photos/models/base/id.dart";
import "package:photos/utils/isolate/isolate_operations.dart";
import "package:synchronized/synchronized.dart";

@pragma('vm:entry-point')
abstract class SuperIsolate {
  Logger get logger;

  Timer? _inactivityTimer;
  final Duration _inactivityDuration = const Duration(seconds: 60);
  int _activeTasks = 0;

  final _initIsolateLock = Lock();
  final _functionLock = Lock();

  bool get isDartUiIsolate;
  bool get shouldAutomaticDispose;
  String get isolateName;

  late dynamic _isolate;
  late ReceivePort _receivePort;
  late SendPort _mainSendPort;

  bool get isIsolateSpawned => _isIsolateSpawned;
  bool _isIsolateSpawned = false;

  Future<void> _initIsolate() async {
    return _initIsolateLock.synchronized(() async {
      if (_isIsolateSpawned) return;

      _receivePort = ReceivePort();

      // Get the root token before spawning the isolate
      final rootToken = RootIsolateToken.instance;
      if (rootToken == null && !isDartUiIsolate) {
        logger.severe('Failed to get RootIsolateToken');
        return;
      }

      try {
        _isolate = isDartUiIsolate
            ? await DartUiIsolate.spawn(_isolateMain, [
                _receivePort.sendPort,
                null,
              ])
            : await Isolate.spawn(_isolateMain, [
                _receivePort.sendPort,
                rootToken,
              ], debugName: isolateName);
        _mainSendPort = await _receivePort.first as SendPort;

        if (shouldAutomaticDispose) _resetInactivityTimer();
        logger.info('initIsolate done');
        _isIsolateSpawned = true;
      } catch (e) {
        logger.severe('Could not spawn isolate', e);
        _isIsolateSpawned = false;
      }
    });
  }

  @pragma('vm:entry-point')
  static void _isolateMain(List<dynamic> args) async {
    final SendPort mainSendPort = args[0] as SendPort;
    final RootIsolateToken? rootToken = args[1] as RootIsolateToken?;

    Logger.root.level = SuperLogging.rootLoggerLevel;
    final IsolateLogger isolateLogger = IsolateLogger();
    Logger.root.onRecord.listen(isolateLogger.onLogRecordInIsolate);
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);
    if (rootToken != null) {
      BackgroundIsolateBinaryMessenger.ensureInitialized(rootToken);
    }
    final logger = Logger('SuperIsolate');
    logger.info('IsolateMain started');

    receivePort.listen((message) async {
      final taskID = message[0] as String;
      final functionIndex = message[1] as int;
      final function = IsolateOperation.values[functionIndex];
      final args = message[2] as Map<String, dynamic>;
      final sendPort = message[3] as SendPort;
      logger.info("Starting isolate operation $function in isolate");

      late final Object data;
      try {
        data = await isolateFunction(function, args);
      } catch (e, stackTrace) {
        data = {'error': e.toString(), 'stackTrace': stackTrace.toString()};
      }
      final logs = List<String>.from(isolateLogger.getLogStringsAndClear());
      sendPort.send({"taskID": taskID, "data": data, "logs": logs});
    });
  }

  /// The common method to run any operation in the isolate.
  /// It sends the [message] to [_isolateMain] and waits for the result.
  /// The actual function executed is [isolateFunction].
  Future<dynamic> runInIsolate(
    IsolateOperation operation,
    Map<String, dynamic> args,
  ) async {
    await _initIsolate();
    return _functionLock.synchronized(() async {
      if (shouldAutomaticDispose) _resetInactivityTimer();

      if (postFunctionlockStop(operation)) {
        return null;
      }

      final completer = Completer<dynamic>();
      final answerPort = ReceivePort();

      _activeTasks++;
      final taskID = newIsolateTaskID(operation.name);
      _mainSendPort.send([taskID, operation.index, args, answerPort.sendPort]);

      answerPort.listen((receivedMessage) {
        if (receivedMessage['taskID'] != taskID) {
          logger.severe("Received isolate message with wrong taskID");
          return;
        }
        _activeTasks--;
        final logs = receivedMessage['logs'] as List<String>;
        IsolateLogger.handLogStringsToMainLogger(logs);
        final data = receivedMessage['data'];
        if (data is Map && data.containsKey('error')) {
          // Handle the error
          final errorMessage = data['error'];
          final errorStackTrace = data['stackTrace'];
          final exception = Exception(errorMessage);
          final stackTrace = StackTrace.fromString(errorStackTrace);
          completer.completeError(exception, stackTrace);
        } else {
          completer.complete(data);
        }
      });

      return completer.future;
    });
  }

  bool postFunctionlockStop(IsolateOperation operation) => false;

  Future<void> cacheData(String key, dynamic value) async {
    await runInIsolate(IsolateOperation.setIsolateCache, {
      'key': key,
      'value': value,
    });
  }

  /// Clears specific data from the isolate's cache
  Future<void> clearCachedData(String key) async {
    await runInIsolate(IsolateOperation.clearIsolateCache, {'key': key});
  }

  Future<void> clearAllCachedData() async {
    await runInIsolate(IsolateOperation.clearAllIsolateCache, {});
  }

  /// Resets a timer that kills the isolate after a certain amount of inactivity.
  ///
  /// Should be called after initialization (e.g. inside `init()`) and after every call to isolate (e.g. inside `_runInIsolate()`)
  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer(_inactivityDuration, () {
      if (_activeTasks > 0) {
        logger.info('Tasks are still running. Delaying isolate disposal.');
        // Optionally, reschedule the timer to check again later.
        _resetInactivityTimer();
      } else {
        logger.info(
          'Isolate has been inactive for ${_inactivityDuration.inSeconds} seconds with no tasks running. Killing isolate.',
        );
        _disposeIsolate();
      }
    });
  }

  Future<void> onDispose() async {}

  void _disposeIsolate() async {
    if (!_isIsolateSpawned) return;
    logger.info('Disposing isolate');
    await onDispose();
    await clearAllCachedData();
    _isIsolateSpawned = false;
    _isolate.kill();
    _receivePort.close();
    _inactivityTimer?.cancel();
  }
}
