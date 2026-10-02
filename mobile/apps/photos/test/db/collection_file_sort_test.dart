import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:photos/db/collections_db.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/file/file_sort_order.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late PathProviderPlatform originalPathProvider;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp("album_sort_db_");
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _DocumentsPath(directory.path);
  });

  tearDownAll(() async {
    await (await CollectionsDB.instance.database).close();
    PathProviderPlatform.instance = originalPathProvider;
    await directory.delete(recursive: true);
  });

  test(
    "sort settings survive database reload and belong to one album",
    () async {
      final album = _album(1);
      final otherAlbum = _album(2);
      await CollectionsDB.instance.insert([album, otherAlbum]);
      for (final sort in FileSortOrder.values) {
        album.mMdPubEncodedJson = jsonEncode({
          ...sort.metadata,
          "coverID": 9,
          "futureField": "preserved",
        });
        await CollectionsDB.instance.insert([album]);
        final loaded = await CollectionsDB.instance.getAllCollections();
        final restored = loaded.singleWhere((c) => c.id == 1);
        expect(identical(restored, album), isFalse);
        expect(restored.pubMagicMetadata.sortOrder, sort);
        expect(restored.pubMagicMetadata.coverID, 9);
        expect(
          jsonDecode(restored.mMdPubEncodedJson!)["futureField"],
          "preserved",
        );
        expect(
          loaded.singleWhere((c) => c.id == 2).pubMagicMetadata.sortOrder,
          FileSortOrder.newestFirst,
        );
      }
    },
  );
}

Collection _album(int id) => Collection(
  id,
  User(id: 1, email: "demo@example.invalid"),
  "",
  null,
  "Demo $id",
  null,
  null,
  CollectionType.album,
  CollectionAttributes(),
  [],
  [],
  1,
);

class _DocumentsPath extends PathProviderPlatform {
  _DocumentsPath(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}
