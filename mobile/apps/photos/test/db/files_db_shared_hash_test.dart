import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:photos/db/files_db.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final files = FilesDB.instance;
  late Directory directory;
  late PathProviderPlatform previousPathProvider;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp("files_db_hash_");
    previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _PathProvider(directory.path);
  });

  tearDownAll(() async {
    await (await files.sqliteAsyncDB).close();
    PathProviderPlatform.instance = previousPathProvider;
    await directory.delete(recursive: true);
  });

  test("matches owned hashes and treats shared hashes as data", () async {
    await files.clearTable();
    await files.insertMultiple([
      _storedFile(uploadedFileID: 1, ownerID: 7, hash: "owned-hash"),
      _storedFile(uploadedFileID: 2, ownerID: 8, hash: "other-owner-hash"),
      _storedFile(uploadedFileID: 3, ownerID: 8, hash: "owned-hash"),
      _storedFile(uploadedFileID: 4, ownerID: 7, hash: "image-hash:video-hash"),
      _storedFile(uploadedFileID: 5, ownerID: 7, hash: "quote'only"),
    ]);

    final ordinary = await files
        .getUserOwnedFilesWithSameHashForGivenListOfFiles([
          _sharedFile("owned-hash"),
          _sharedFile("other-owner-hash"),
          _sharedFile("image-hash:video-hash"),
        ], 7);
    expect(
      ordinary.keys,
      unorderedEquals(["owned-hash", "image-hash:video-hash"]),
    );
    expect(ordinary["owned-hash"]?.uploadedFileID, 1);
    expect(ordinary["owned-hash"]?.ownerID, 7);
    expect(ordinary["image-hash:video-hash"]?.uploadedFileID, 4);

    final quoted = await files.getUserOwnedFilesWithSameHashForGivenListOfFiles(
      [_sharedFile("quote'only")],
      7,
    );
    expect(quoted.keys, ["quote'only"]);
    expect(quoted["quote'only"]?.uploadedFileID, 5);
  });

  test("merges results across hash lookup batches", () async {
    await files.clearTable();
    const count = 1001;
    final hashes = List.generate(count, (index) => "hash-$index");
    await files.insertMultiple([
      for (var index = 0; index < count; index++)
        _storedFile(uploadedFileID: index + 1, ownerID: 7, hash: hashes[index]),
    ]);

    final matches = await files
        .getUserOwnedFilesWithSameHashForGivenListOfFiles(
          hashes.map(_sharedFile).toList(),
          7,
        );

    expect(matches, hasLength(count));
    expect(matches["hash-1000"]?.uploadedFileID, 1001);
  });
}

EnteFile _storedFile({
  required int uploadedFileID,
  required int ownerID,
  required String hash,
}) => EnteFile()
  ..uploadedFileID = uploadedFileID
  ..ownerID = ownerID
  ..collectionID = 10
  ..title = "photo.jpg"
  ..fileType = FileType.image
  ..creationTime = 100
  ..modificationTime = 100
  ..hash = hash;

EnteFile _sharedFile(String hash) => EnteFile()
  ..ownerID = 9
  ..hash = hash;

class _PathProvider extends PathProviderPlatform {
  _PathProvider(this.path);

  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}
