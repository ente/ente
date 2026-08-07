import "package:ffmpeg_kit_flutter/ffmpeg_kit_config.dart";
import "package:logging/logging.dart";
import "package:photos/models/ffmpeg/ffprobe_props.dart";
import "package:photos/services/isolated_ffmpeg_service.dart";

final _logger = Logger("VideoMetadata");

/// content:// URI paths are supported only on Android.
Future<FFProbeProps?> getVideoProps(String path) async {
  try {
    String? ffprobePath = path;
    if (path.startsWith("content://")) {
      ffprobePath = await FFmpegKitConfig.getSafParameterForRead(path);
      if (ffprobePath == null || ffprobePath.isEmpty) {
        throw Exception("FFmpegKitConfig.getSafParameterForRead() failed");
      }
    }
    final stopwatch = Stopwatch()..start();
    final mediaInfo = await IsolatedFfmpegService.instance.getVideoInfo(
      ffprobePath,
    );
    if (mediaInfo.isEmpty) {
      return null;
    }
    final properties = FFProbeProps.parseData(mediaInfo);
    _logger.info("getVideoProps took ${stopwatch.elapsedMilliseconds}ms");
    return properties;
  } catch (e, s) {
    _logger.severe("Failed to get video properties", e, s);
    return null;
  }
}
