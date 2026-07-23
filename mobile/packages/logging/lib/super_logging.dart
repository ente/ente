import 'dart:async';
import 'dart:collection';
import 'dart:core';
import 'dart:io';

import "package:dio/dio.dart";
import 'package:ente_logging/tunneled_transport.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:logging/logging.dart' as log;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Type definition for functions that may return a value or Future
typedef FutureOrVoidCallback = dynamic Function();

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

extension SuperLogRecord on log.LogRecord {
  String toPrettyString([String? extraLines]) {
    final header = "[$loggerName][$level] [$time]";

    var msg = "$header $message";

    if (error != null) {
      if (error is DioException) {
        final e = error as DioException;
        final String? id = e.requestOptions.headers['x-request-id'] as String?;
        if (id != null) {
          msg += "\n⤷ id: $id ";
        }
        if (e.response?.data != null) {
          msg += "\n⤷ type: ${e.type}\n⤷ error: ${e.response?.data}";
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
  /// The DSN for a Sentry app.
  /// This can be obtained from the Sentry apps's "settings > Client Keys (DSN)" page.
  ///
  /// Only logs containing errors are sent to sentry.
  /// Errors can be caught using a try-catch block, like so:
  ///
  /// ```
  /// final logger = Logger("main");
  ///
  /// try {
  ///   // do something dangerous here
  /// } catch(e, trace) {
  ///   logger.info("Huston, we have a problem", e, trace);
  /// }
  /// ```
  ///
  /// If this is [null], Sentry logger is completely disabled (default).
  String? sentryDsn;

  String? tunnel;

  /// A built-in retry mechanism for sending errors to sentry.
  ///
  /// This parameter defines the time to wait for, before retrying.
  Duration sentryRetryDelay;

  /// Path of the directory where log files will be stored.
  ///
  /// If this is [null], file logging is completely disabled (default).
  ///
  /// If this is an empty string (['']),
  /// then a 'logs' directory will be created in [getTemporaryDirectory()].
  ///
  /// A non-empty string will be treated as an explicit path to a directory.
  ///
  /// The chosen directory can be accessed using [SuperLogging.logFile.parent].
  String? logDirPath;

  /// The maximum number of log files inside [logDirPath].
  ///
  /// One log file is created per day.
  /// Older log files are deleted automatically.
  int maxLogFiles;

  /// Whether to enable super logging features in debug mode.
  ///
  /// Sentry and file logging are typically not needed in debug mode,
  /// where a complete logcat is available.
  bool enableInDebugMode;

  /// If provided, super logging will invoke this function, and
  /// any uncaught errors during its execution will be reported.
  ///
  /// Works by using [FlutterError.onError] and [runZoned].
  FutureOrVoidCallback? body;

  /// The date format for storing log files.
  ///
  /// `DateFormat('y-M-d')` by default.
  DateFormat? dateFmt;

  String prefix;

  LogConfig({
    this.sentryDsn,
    this.tunnel,
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
  /// The logger for SuperLogging
  static final $ = log.Logger('ente_logging');

  /// The current super logging configuration
  static late LogConfig config;

  static late SharedPreferences _preferences;

  static const keyShouldReportErrors = "should_report_errors";

  static const keyAnonymousUserID = "anonymous_user_id";

  static Future<void> main([LogConfig? appConfig]) async {
    appConfig ??= LogConfig();
    SuperLogging.config = appConfig;

    WidgetsFlutterBinding.ensureInitialized();
    _preferences = await SharedPreferences.getInstance();

    appVersion ??= await getAppVersion();

    final enable = appConfig.enableInDebugMode || kReleaseMode;
    sentryIsEnabled =
        enable && appConfig.sentryDsn != null && shouldReportErrors();
    fileIsEnabled = enable && appConfig.logDirPath != null;

    if (fileIsEnabled) {
      await setupLogDir();
    }
    if (sentryIsEnabled) {
      setupSentry().ignore();
    }

    log.Logger.root.level = log.Level.ALL;
    log.Logger.root.onRecord.listen(onLogRecord);

    if (!enable) {
      $.info("detected debug mode; sentry & file logging disabled.");
    }
    if (fileIsEnabled) {
      $.info("log file for today: $logFile with prefix ${appConfig.prefix}");
    }
    if (sentryIsEnabled) {
      $.info("sentry uploader started");
    }

    if (appConfig.body == null) return;

    if (enable && sentryIsEnabled) {
      await SentryFlutter.init((options) {
        options.anrEnabled = true;
        options.anrTimeoutInterval = const Duration(seconds: 5);
        options.dsn = appConfig!.sentryDsn;
        options.httpClient = http.Client();
        if (appConfig.tunnel != null) {
          options.transport = TunneledTransport(
            Uri.parse(appConfig.tunnel!),
            options,
          );
        }
      }, appRunner: () => appConfig!.body!());
    } else {
      await appConfig.body!();
    }
  }

  static void setUserID(String userID) async {
    if (config.sentryDsn != null) {
      Sentry.configureScope((scope) => scope.setUser(SentryUser(id: userID)));
      $.info("setting sentry user ID to: $userID");
    }
  }

  static Future<void> _sendErrorToSentry(
    Object error,
    StackTrace? stack,
  ) async {
    try {
      await Sentry.captureException(error, stackTrace: stack);
    } catch (e) {
      $.info('Sending report to sentry.io failed: $e');
      $.info('Original error: $error');
    }
  }

  static String _lastExtraLines = '';

  static Future onLogRecord(log.LogRecord rec) async {
    // log misc info if it changed
    String? extraLines = "app version: '$appVersion'\n";
    if (extraLines != _lastExtraLines) {
      _lastExtraLines = extraLines;
    } else {
      extraLines = null;
    }

    final str = "${config.prefix} ${rec.toPrettyString(extraLines)}";

    // write to stdout
    printLog(str);

    // push to log queue
    if (fileIsEnabled) {
      fileQueueEntries.add('$str\n');
      if (fileQueueEntries.length == 1) {
        flushQueue();
      }
    }

    // add error to sentry queue
    if (sentryIsEnabled && rec.error != null) {
      _sendErrorToSentry(rec.error!, null).ignore();
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

  // Logs on must be chunked or they get truncated otherwise
  // See https://github.com/flutter/flutter/issues/22665
  static var logChunkSize = 800;

  static void printLog(String text) {
    text.chunked(logChunkSize).forEach(debugPrint);
  }

  /// A queue to be consumed by [setupSentry].
  static final sentryQueueControl = StreamController<Error>();

  /// Whether sentry logging is currently enabled or not.
  static bool sentryIsEnabled = false;

  static Future<void> setupSentry() async {
    $.info("Setting up sentry");
    SuperLogging.setUserID(await _getOrCreateAnonymousUserID());
    await for (final error in sentryQueueControl.stream.asBroadcastStream()) {
      try {
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

  static bool shouldReportErrors() {
    if (_preferences.containsKey(keyShouldReportErrors)) {
      return _preferences.getBool(keyShouldReportErrors)!;
    } else {
      return kDebugMode;
    }
  }

  static Future<void> setShouldReportErrors(bool value) {
    return _preferences.setBool(keyShouldReportErrors, value);
  }

  static Future<String> _getOrCreateAnonymousUserID() async {
    if (!_preferences.containsKey(keyAnonymousUserID)) {
      //ignore: prefer_const_constructors
      await _preferences.setString(keyAnonymousUserID, Uuid().v4());
    }
    return _preferences.getString(keyAnonymousUserID)!;
  }

  /// The log file currently in use.
  static File? logFile;

  /// Whether file logging is currently enabled or not.
  static bool fileIsEnabled = false;

  static Future<void> setupLogDir() async {
    var dirPath = config.logDirPath;

    // choose [logDir]
    if (dirPath == null || dirPath.isEmpty) {
      final root = await getExternalStorageDirectory();
      dirPath = join(root!.path, 'logs');
    }

    // create [logDir]
    final dir = Directory(dirPath);
    await dir.create(recursive: true);

    final files = <File>[];
    final dates = <File, DateTime>{};

    // collect all log files with valid names
    await for (final file in dir.list()) {
      try {
        final date = config.dateFmt!.parse(basename(file.path));
        dates[file as File] = date;
        files.add(file);
      } on Exception catch (_) {}
    }
    final nowTime = DateTime.now();

    // delete old log files, if [maxLogFiles] is exceeded.
    if (files.length > config.maxLogFiles) {
      // sort files based on ascending order of date (older first)
      files.sort(
        (a, b) => (dates[a] ?? nowTime).compareTo((dates[b] ?? nowTime)),
      );

      final extra = files.length - config.maxLogFiles;
      final toDelete = files.sublist(0, extra);

      for (final file in toDelete) {
        try {
          $.fine("deleting log file ${file.path}");
          await file.delete();
        } on Exception catch (_) {}
      }
    }

    logFile = File(
      join(dirPath, "${config.dateFmt!.format(DateTime.now())}.txt"),
    );
  }

  /// Current app version, obtained from package_info plugin.
  ///
  /// See: [getAppVersion]
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
    return pkgName.endsWith("fdroid");
  }
}
