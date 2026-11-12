import "dart:io";

import "package:logging/logging.dart";
import "package:photo_manager/photo_manager.dart";
import "package:photos/utils/device_info.dart";

final _logger = Logger("gallery_save_video");

Future<AssetEntity> saveVideoToGallery(
  File file, {
  required String title,
  DateTime? creationDate,
}) async {
  final milliseconds = creationDate?.millisecondsSinceEpoch;
  final requiresAndroidDateUpdate =
      Platform.isAndroid &&
      milliseconds != null &&
      milliseconds >= -0x80000000 &&
      milliseconds <= 0x7fffffff;
  final asset = await PhotoManager.editor.saveVideo(
    file,
    title: title,
    creationDate: requiresAndroidDateUpdate ? null : creationDate,
  );
  if (!requiresAndroidDateUpdate || creationDate == null) {
    return asset;
  }
  try {
    if (await isAndroidSDKVersionLowerThan(29)) {
      return asset;
    }
    final timestamp = creationDate.millisecondsSinceEpoch;
    final dateAtSecondResolution = DateTime.fromMillisecondsSinceEpoch(
      timestamp - timestamp % 1000,
      isUtc: creationDate.isUtc,
    );
    return await PhotoManager.editor.android.updateCreationDate(
      entity: asset,
      creationDate: dateAtSecondResolution,
    );
  } catch (error, stackTrace) {
    _logger.warning(
      "Failed to update the capture date of a saved video",
      error,
      stackTrace,
    );
    return asset;
  }
}
