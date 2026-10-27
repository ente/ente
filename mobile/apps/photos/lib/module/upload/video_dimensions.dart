import "dart:io";

import "package:logging/logging.dart";
import "package:native_video_editor/native_video_editor.dart";

final _logger = Logger("VideoUploadDimensions");

Future<({int width, int height})?> getVideoUploadDimensions(
  File sourceFile, {
  NativeVideoInfo? sourceVideoInfo,
}) async {
  try {
    final info =
        sourceVideoInfo ??
        await NativeVideoEditor.inspectVideo(sourceFile.path);
    return (width: info.displayWidth, height: info.displayHeight);
  } catch (e, s) {
    _logger.warning("Failed to read upload video dimensions", e, s);
  }
  return null;
}
