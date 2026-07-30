import "package:photos/models/file/file.dart";
import "package:photos/module/download/file.dart";

Future<String?> getPickerResultUri(EnteFile file) async {
  if (!file.isSharedMediaToAppSandbox) {
    final mediaUri = await (await file.getAsset)?.getMediaUrl();
    if (mediaUri != null) return mediaUri;
  }
  return (await getFile(file))?.uri.toString();
}
