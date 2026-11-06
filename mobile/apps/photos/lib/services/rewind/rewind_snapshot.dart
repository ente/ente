import "dart:io";

import "package:path/path.dart" as path;
import "package:photos/core/configuration.dart";
import "package:photos/services/rewind/rewind_request.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;

Future<String> exportRewindSnapshot() async {
  final snapshot = Directory(
    path.join(Configuration.instance.getTempDirectory(), "rewind_snapshot"),
  );
  await snapshot.create(recursive: true);
  final request = await buildRewindRequest(DateTime.now());
  await File(
    path.join(snapshot.path, "request.json"),
  ).writeAsBytes(await rust.encodeRewindRequest(request: request));
  return snapshot.path;
}
