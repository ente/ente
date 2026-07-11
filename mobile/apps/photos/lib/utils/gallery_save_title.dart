import "dart:io";

import "package:photos/core/constants.dart";
import "package:photos/utils/device_info.dart";

Future<String> getMediaStoreCompatibleTitle(String title) async {
  if (!Platform.isAndroid) {
    return title;
  }
  final sanitizedTitle = _sanitizePreAndroid11MediaStoreTitle(title);
  if (sanitizedTitle == title) {
    return title;
  }
  if (await isAndroidSDKVersionLowerThan(android11SDKINT)) {
    return sanitizedTitle;
  }
  return title;
}

String _sanitizePreAndroid11MediaStoreTitle(String title) {
  final fragmentIndex = title.lastIndexOf("#");
  if (fragmentIndex < 0 || title.lastIndexOf(".") <= fragmentIndex) {
    return title;
  }
  // The legacy MIME guesser treats # as a URL fragment delimiter.
  return title.replaceAll("#", "_");
}
