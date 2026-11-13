import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:photos/db/offline_files_db.dart";

void main() {
  late Directory tempDir;
  late PathProviderPlatform previousPathProvider;

  setUpAll(() async {
    previousPathProvider = PathProviderPlatform.instance;
    tempDir = await Directory.systemTemp.createTemp("offline_files_db_test_");
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDownAll(() async {
    PathProviderPlatform.instance = previousPathProvider;
    await tempDir.delete(recursive: true);
  });

  test(
    "handles local ID lookups larger than a single SQL bind batch",
    () async {
      final localIds = List.generate(1200, (index) => "local-id-$index");

      final localIdToIntId = await OfflineFilesDB.instance.ensureLocalIntIds(
        localIds,
      );

      expect(localIdToIntId, hasLength(localIds.length));
      expect(localIdToIntId.keys, containsAll(localIds));

      final localIntIds = localIdToIntId.values.toList();
      final localIntIdToLocalId = await OfflineFilesDB.instance
          .getLocalIdsForIntIds(localIntIds);

      expect(localIntIdToLocalId, hasLength(localIds.length));
      for (final localId in localIds) {
        final localIntId = localIdToIntId[localId];
        expect(localIntIdToLocalId[localIntId], localId);
      }
    },
  );
}

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.documentsPath);

  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}
