import "dart:io";

import "package:logging/logging.dart";
import "package:photos/models/ffmpeg/ffprobe_props.dart";
import "package:photos/services/isolated_ffmpeg_service.dart";

final _logger = Logger("VideoMetadata");

Future<FFProbeProps?> getVideoProps(File file) async {
  try {
    final stopwatch = Stopwatch()..start();
    final mediaInfo = await IsolatedFfmpegService.instance.getVideoInfo(
      file.path,
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
