import "package:photos/core/configuration.dart";
import "package:photos/service_locator.dart";

extension UserConfig on Configuration {
  int getUserIDV2() {
    final int? userID = getUserID();
    if (userID == null && !isLocalGalleryMode) {
      throw StateError("Missing user ID in online mode");
    }
    return userID ?? -1;
  }
}
