import "dart:io";

import "package:logging/logging.dart";
import "package:path/path.dart" as path;
import "package:path_provider/path_provider.dart";
import "package:shared_preferences/shared_preferences.dart";

final _logger = Logger("Rewind2025Leftovers");

Future<void> removeRewind2025Leftovers(SharedPreferences prefs) async {
  try {
    await prefs.remove("ls.wrapped_2025_resume_index");
    await prefs.remove("ls.wrapped_2025_complete");
    final cacheDirectory = Directory(
      path.join((await getApplicationSupportDirectory()).path, "wrapped_cache"),
    );
    if (await cacheDirectory.exists()) {
      await cacheDirectory.delete(recursive: true);
    }
  } catch (e, s) {
    _logger.warning("Failed to remove Rewind 2025 leftovers", e, s);
  }
}
