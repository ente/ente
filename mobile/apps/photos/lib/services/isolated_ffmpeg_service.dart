import "dart:async";
import "dart:isolate";
import "package:ffmpeg_kit_flutter/ffmpeg_kit.dart";
import "package:ffmpeg_kit_flutter/ffmpeg_kit_config.dart";
import "package:ffmpeg_kit_flutter/ffmpeg_session.dart";
import "package:ffmpeg_kit_flutter/ffprobe_kit.dart";
import "package:flutter/services.dart";
import "package:photos/service_locator.dart";
import "package:photos/utils/ffprobe_util.dart";

class IsolatedFfmpegService {
  IsolatedFfmpegService._privateConstructor();

  static final IsolatedFfmpegService instance =
      IsolatedFfmpegService._privateConstructor();

  Future<Map> runFfmpeg(String command) async {
    final rootIsolateToken = RootIsolateToken.instance!;
    return await Isolate.run<Map>(() => _ffmpegRun(command, rootIsolateToken));
  }

  /// Run FFmpeg with session ID callback for cancellation support.
  /// Uses a completion port registered on the root isolate.
  Future<Map> runFfmpegCancellable(
    String command,
    void Function(int sessionId) onSessionStarted,
  ) async {
    if (!flagService.stopStreamProcess) {
      return await runFfmpeg(command);
    }

    final rootIsolateToken = RootIsolateToken.instance!;
    final port = ReceivePort();
    final completionPort = ReceivePort();
    final completer = Completer<Map>();

    port.listen((msg) {
      if (msg is int) {
        FFmpegKit.registerSessionCompletionPort(msg, completionPort.sendPort);
        onSessionStarted(msg);
      }
    });

    // ignore: unawaited_futures
    completionPort.first.then((result) {
      if (result is Map) {
        completer.complete({
          "returnCode": result["returnCode"],
          "output": result["output"],
        });
      }
      completionPort.close();
      port.close();
    });

    await Isolate.spawn(_ffmpegRunCancellable, (
      command,
      port.sendPort,
      rootIsolateToken,
    ));

    return completer.future;
  }

  Future<Map> getVideoInfo(String file) async {
    final rootIsolateToken = RootIsolateToken.instance!;
    return await Isolate.run<Map>(() => _getVideoProps(file, rootIsolateToken));
  }

  Future<double?> getSessionProgress({
    required int? sessionId,
    required Duration? duration,
  }) async {
    if (sessionId == null || duration == null) return null;
    if (duration.inMilliseconds <= 0) return null;

    final session = await FFmpegKitConfig.getSession(sessionId);
    if (session == null || session is! FFmpegSession) return null;

    final stats = await session.getStatistics();
    if (stats.isEmpty) return null;

    final ms = stats.last.getTime().toDouble();
    return (ms / duration.inMilliseconds).clamp(0.0, 1.0);
  }
}

@pragma('vm:entry-point')
Future<Map> _getVideoProps(
  String filePath,
  RootIsolateToken rootIsolateToken,
) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
  final session = await FFprobeKit.getMediaInformation(filePath);
  final mediaInfo = session.getMediaInformation();

  if (mediaInfo == null) {
    return {};
  }

  final metadata = await FFProbeUtil.getMetadata(mediaInfo);
  return metadata;
}

@pragma('vm:entry-point')
Future<Map> _ffmpegRun(String value, RootIsolateToken rootIsolateToken) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
  final session = await FFmpegKit.execute(value, true);
  final returnCode = await session.getReturnCode();
  final output = await session.getOutput();

  return {"returnCode": returnCode?.getValue(), "output": output};
}

@pragma('vm:entry-point')
Future<void> _ffmpegRunCancellable(
  (String, SendPort, RootIsolateToken) params,
) async {
  final (command, sendPort, token) = params;
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);

  final session = await FFmpegKit.executeAsync(command);
  final sessionId = session.getSessionId();
  if (sessionId != null) sendPort.send(sessionId);
}
