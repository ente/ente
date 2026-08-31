import 'dart:async';
import 'dart:collection';
import 'dart:core';
import 'dart:io';

import "package:dio/dio.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photos/core/error-reporting/tunneled_transport.dart';
import "package:photos/core/exceptions.dart";
import 'package:photos/models/typedefs.dart';
import "package:photos/utils/device_info.dart";
import "package:photos/utils/ram_check_util.dart";
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

extension SuperString on String {
  Iterable<String> chunked(int chunkSize) sync* {
    var start = 0;

    while (true) {
      final stop = start + chunkSize;
      if (stop > length) break;
      yield substring(start, stop);
      start = stop;
    }

    if (start < length) {
      yield substring(start);
    }
  }
}

extension SuperLogRecord on LogRecord {
  String toPrettyString([String? extraLines, bool inIsolate = false]) {
    final header =
        "[$loggerName${inIsolate ? " (in isolate)" : ""}] [$level] [$time]";

    var msg = "$header $message";

    if (error != null) {
      if (error is DioException) {
        final e = error as DioException;
        final String? id = e.requestOptions.headers['x-request-id'] as String?;
        if (id != null) {
          msg += "\n⤷ id: $id ";
        }
        final responseData = e.response?.data;
        if (responseData != null) {
          final contentLength = int.tryParse(
            e.response?.headers.value('content-length') ?? '',
          );
          if (contentLength != null && contentLength > 102400) {
            msg +=
                "\n⤷ type: ${e.type}\n⤷ error: [response too large: $contentLength bytes]";
          } else {
            msg += "\n⤷ type: ${e.type}\n⤷ error: $responseData";
          }
        } else {
          msg += "\n⤷ type: ${e.type}\n⤷ error: $error";
        }
      } else {
        msg += "\n⤷ type: ${error.runtimeType}\n⤷ error: $error";
      }
    }
    if (stackTrace != null) {
      msg += "\n⤷ trace: $stackTrace";
    }

    for (var line in extraLines?.split('\n') ?? []) {
      msg += '\n$header $line';
    }

    return msg;
  }
}

class LogConfig {
  String? sentryDsn;

  String? tunnel;

  Duration? sentryInitTimeout;

  Duration sentryRetryDelay;

  // Null disables file logging; empty uses the default directory.
  String? logDirPath;

  int maxLogFiles;

  bool enableInDebugMode;

  FutureOrVoidCallback? body;

  DateFormat? dateFmt;

  String prefix;

  LogConfig({
    this.sentryDsn,
    this.tunnel,
    this.sentryInitTimeout,
    this.sentryRetryDelay = const Duration(seconds: 30),
    this.logDirPath,
    this.maxLogFiles = 10,
    this.enableInDebugMode = false,
    this.body,
    this.dateFmt,
    this.prefix = "",
  }) {
    dateFmt ??= DateFormat("y-M-d");
  }
}

class SuperLogging {
  static final $ = Logger('ente_logging');

  static final String _loggerPrefixDefine = const String.fromEnvironment(
    'ENTE_LOGGER_PREFIX',
  ).trim().toLowerCase();

  static late LogConfig config;

  static late SharedPreferences _preferences;

  static bool _isRootLogListenerRegistered = false;

  static const keyShouldReportCrashes = "should_report_crashes";

  static Future<void> main([LogConfig? appConfig]) async {
    appConfig ??= LogConfig();
    SuperLogging.config = appConfig;

    WidgetsFlutterBinding.ensureInitialized();
    _preferences = await SharedPreferences.getInstance();

    appVersion ??= await getAppVersion();
    final isFDroidClient = await isFDroidBuild();
    if (isFDroidClient) {
      appConfig.sentryDsn = null;
      appConfig.tunnel = null;
    }

    final enable = appConfig.enableInDebugMode || kReleaseMode;
    sentryIsEnabled =
        enable &&
        appConfig.sentryDsn != null &&
        !isFDroidClient &&
        shouldReportCrashes();
    fileIsEnabled = enable && appConfig.logDirPath != null;

    if (fileIsEnabled) {
      await setupLogDir();
    }
    if (sentryIsEnabled) {
      setupSentry().ignore();
    }

    Logger.root.level = rootLoggerLevel;
    EnteWatch.setLogLevel(_terminalLoggerLevel);
    if (!_isRootLogListenerRegistered) {
      Logger.root.onRecord.listen(onLogRecord);
      _isRootLogListenerRegistered = true;
    }

    if (isFDroidClient) {
      assert(
        sentryIsEnabled == false,
        "sentry dsn should be disabled for "
        "f-droid config  ${appConfig.sentryDsn} & ${appConfig.tunnel}",
      );
    }

    if (!enable) {
      $.info("detected debug mode; sentry & file logging disabled.");
    }
    if (fileIsEnabled) {
      $.info("log file for today: $logFile with prefix ${appConfig.prefix}");
    }
    if (sentryIsEnabled) {
      $.info("sentry uploader started");
    }

    unawaited(
      getDeviceInfo().then((info) {
        $.info("Device Info: $info");
      }),
    );

    unawaited(
      checkDeviceTotalRAM().then((ram) {
        if (ram != null) $.info("Device RAM: ${ram}MB");
      }),
    );

    if (appConfig.body == null) return;

    if (enable && sentryIsEnabled) {
      final sentryInitTimeout = appConfig.sentryInitTimeout;
      if (sentryInitTimeout == null) {
        await SentryFlutter.init(
          _configureSentryOptions,
          appRunner: () => kDebugMode
              ? _runWithUnhandledErrorLogging(appConfig!.body!)
              : appConfig!.body!(),
        );
      } else {
        try {
          await SentryFlutter.init(
            _configureSentryOptions,
          ).timeout(sentryInitTimeout);
        } catch (e) {
          sentryIsEnabled = false;
          $.warning(
            "Sentry init did not complete, running body without it: $e",
          );
        }
        if (kDebugMode) {
          await _runWithUnhandledErrorLogging(appConfig.body!);
        } else {
          await appConfig.body!();
        }
      }
    } else {
      if (kDebugMode) {
        // Keep debug-only until we're sure this doesn't cause regressions.
        await _runWithUnhandledErrorLogging(appConfig.body!);
      } else {
        await appConfig.body!();
      }
    }
  }

  static void _configureSentryOptions(SentryFlutterOptions options) {
    options.dsn = config.sentryDsn;
    options.anrEnabled = true;
    options.anrTimeoutInterval = const Duration(seconds: 5);
    options.httpClient = http.Client();
    final tunnel = config.tunnel;
    if (tunnel != null) {
      options.transport = TunneledTransport(Uri.parse(tunnel), options);
    }
    options.beforeSend = (SentryEvent event, Hint hint) async {
      final dynamic error = event.throwable;
      if (error != null && _shouldSkipSentry(error)) {
        return null;
      }
      return event;
    };
  }

  static Future<void> _runWithUnhandledErrorLogging(
    FutureOrVoidCallback body,
  ) async {
    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      previousFlutterError?.call(details);
      $.severe("Unhandled Flutter error", details.exception, details.stack);
    };
    WidgetsBinding.instance.platformDispatcher.onError =
        (Object error, StackTrace stack) {
          $.severe("Unhandled platform error", error, stack);
          return false;
        };

    await runZonedGuarded(() async => body(), (Object error, StackTrace stack) {
      $.severe("Unhandled zone error", error, stack);
    });
  }

  static Future<void> setUserID(String userID) async {
    if (config.sentryDsn != null) {
      $.finest("setting sentry user ID to: $userID");
      Sentry.configureScope(
        (scope) => scope
            .setUser(SentryUser(id: userID))
            .onError(
              (e, s) => $.warning("failed to configure scope user", e, s),
            ),
      );
    }
  }

  static bool _shouldSkipSentry(Object error) {
    if (error is DioException) {
      return true;
    }
    final bool result =
        error is LocallyHandledError ||
        error is TaskQueueTimeoutException ||
        error is TaskQueueOverflowException ||
        error is TaskQueueCancelledException;
    if (kDebugMode && result) {
      $.info('Not sending error to sentry: $error');
    }
    return result;
  }

  static Future<void> _sendErrorToSentry(
    Object error,
    StackTrace? stack, {
    LogRecord? rec,
  }) async {
    try {
      if (kDebugMode && error is StackTrace) {
        _reportInvalidLoggerUsageInDebug(rec, error);
      }

      if (_shouldSkipSentry(error)) {
        return;
      }

      final executionContext = _getExecutionContext();

      if (rec != null) {
        await Sentry.captureException(
          error,
          stackTrace: stack,
          withScope: (scope) {
            scope.setContexts('log_details', {'message': rec.message});
            scope.setTag('logger', rec.loggerName);
            scope.setTag('level', rec.level.name);
            scope.setTag('execution_context', executionContext);
          },
        );
      } else {
        await Sentry.captureException(
          error,
          stackTrace: stack,
          withScope: (scope) {
            scope.setTag('execution_context', executionContext);
          },
        );
      }
    } catch (e) {
      $.info('Sending report to sentry failed: $e');
      $.info('Original error: $error');
    }
  }

  static void _reportInvalidLoggerUsageInDebug(
    LogRecord? rec,
    StackTrace stack,
  ) {
    assert(() {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError(
            "Logger call passed a StackTrace as the error argument. "
            "Use logger.warning(message, error, stackTrace) or "
            "logger.severe(message, error, stackTrace)."
            "${rec == null ? '' : ' Logger: ${rec.loggerName}.'}",
          ),
          stack: stack,
          library: "SuperLogging",
        ),
      );
      return true;
    }());
  }

  static String _getExecutionContext() {
    final prefix = config.prefix.trim();
    if (prefix.isEmpty) return 'foreground';
    if (prefix.contains('[bg]')) return 'background';
    if (prefix.contains('[fbg]')) return 'firebase_background';
    return 'unknown';
  }

  static String _lastExtraLines = '';

  static const Level rootLoggerLevel = kDebugMode ? Level.ALL : Level.INFO;

  static const _logLevelDefine = String.fromEnvironment('ENTE_LOG_LEVEL');

  static final Level _terminalLoggerLevel = _levelFromEnv(
    _logLevelDefine,
    rootLoggerLevel,
  );

  static Level _levelFromEnv(String value, Level fallback) {
    final levelName = value.trim().toLowerCase();
    return Level.LEVELS.firstWhere(
      (level) => level.name.toLowerCase() == levelName,
      orElse: () => fallback,
    );
  }

  static bool shouldPrintLogRecord(LogRecord rec) {
    final matchesPrefix =
        _loggerPrefixDefine.isEmpty ||
        rec.loggerName.toLowerCase().startsWith(_loggerPrefixDefine);
    return matchesPrefix && rec.level.value >= _terminalLoggerLevel.value;
  }

  static Future onLogRecord(LogRecord rec) async {
    String? extraLines = "app version: '$appVersion'\n";
    if (extraLines != _lastExtraLines) {
      _lastExtraLines = extraLines;
    } else {
      extraLines = null;
    }

    final str = (config.prefix) + " " + rec.toPrettyString(extraLines);

    if (shouldPrintLogRecord(rec)) {
      printLog(str);
    }

    saveLogString(str, rec.error, rec: rec);
  }

  static void saveLogString(
    String str,
    Object? error, {
    LogRecord? rec,
    StackTrace? stackTrace,
  }) {
    if (fileIsEnabled) {
      fileQueueEntries.add(str + '\n');
      if (fileQueueEntries.length == 1) {
        flushQueue();
      }
    }

    if (sentryIsEnabled && error != null) {
      _sendErrorToSentry(
        error,
        rec?.stackTrace ?? stackTrace,
        rec: rec,
      ).ignore();
    }
  }

  static final Queue<String> fileQueueEntries = Queue();
  static bool isFlushing = false;

  static void flushQueue() async {
    if (isFlushing || logFile == null) {
      return;
    }
    isFlushing = true;
    final entry = fileQueueEntries.removeFirst();
    await logFile!.writeAsString(entry, mode: FileMode.append, flush: true);
    isFlushing = false;
    if (fileQueueEntries.isNotEmpty) {
      flushQueue();
    }
  }

  // Chunk long logs to avoid truncation.
  // https://github.com/flutter/flutter/issues/22665
  static var logChunkSize = 800;

  static void printLog(String text) {
    if (kDebugMode) {
      // ignore: avoid_print
      text.chunked(logChunkSize).forEach(print);
    }
  }

  static final sentryQueueControl = StreamController<Error>();

  static bool sentryIsEnabled = false;

  static Future<void> setupSentry() async {
    await for (final error in sentryQueueControl.stream.asBroadcastStream()) {
      try {
        if (_shouldSkipSentry(error)) {
          continue;
        }
        await Sentry.captureException(error);
      } catch (e) {
        $.fine(
          "sentry upload failed; will retry after ${config.sentryRetryDelay}",
        );
        doSentryRetry(error);
      }
    }
  }

  static void doSentryRetry(Error error) async {
    await Future.delayed(config.sentryRetryDelay);
    sentryQueueControl.add(error);
  }

  static bool shouldReportCrashes() {
    if (_preferences.containsKey(keyShouldReportCrashes)) {
      return _preferences.getBool(keyShouldReportCrashes)!;
    } else {
      return true;
    }
  }

  static Future<void> setShouldReportCrashes(bool value) {
    return _preferences.setBool(keyShouldReportCrashes, value);
  }

  static File? logFile;

  static bool fileIsEnabled = false;

  static Future<void> setupLogDir() async {
    var dirPath = config.logDirPath;

    if (dirPath == null || dirPath.isEmpty) {
      final root = await getExternalStorageDirectory();
      dirPath = '${root!.path}/logs';
    }

    final dir = Directory(dirPath);
    await dir.create(recursive: true);

    final files = <File>[];
    final dates = <File, DateTime>{};

    await for (final file in dir.list()) {
      try {
        final date = config.dateFmt!.parse(basename(file.path));
        dates[file as File] = date;
        files.add(file);
      } on FormatException catch (_) {}
    }
    final nowTime = DateTime.now();

    if (files.length > config.maxLogFiles) {
      files.sort(
        (a, b) => (dates[a] ?? nowTime).compareTo((dates[b] ?? nowTime)),
      );

      final extra = files.length - config.maxLogFiles;
      final toDelete = files.sublist(0, extra);

      for (final file in toDelete) {
        try {
          $.fine("deleting log file ${file.path}");
          await file.delete();
        } catch (_) {}
      }
    }

    logFile = File("$dirPath/${config.dateFmt!.format(DateTime.now())}.log");
  }

  static String? appVersion;

  static Future<String> getAppVersion() async {
    final pkgInfo = await PackageInfo.fromPlatform();
    return "${pkgInfo.version}+${pkgInfo.buildNumber}";
  }

  // disable sentry on f-droid. We need to make it opt-in preference
  static Future<bool> isFDroidBuild() async {
    if (!Platform.isAndroid) {
      return false;
    }
    final pkgName = (await PackageInfo.fromPlatform()).packageName;
    return pkgName.startsWith("io.ente.photos.fdroid");
  }
}
