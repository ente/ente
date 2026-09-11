import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:path_provider_platform_interface/path_provider_platform_interface.dart";
import "package:photos/db/files_db.dart";
import "package:photos/models/file/file.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final files = FilesDB.instance;
  late Directory directory;
  late PathProviderPlatform previousPathProvider;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp("offline_metadata_");
    previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _PathProvider(directory.path);
  });

  tearDownAll(() async {
    await (await files.sqliteAsyncDB).close();
    PathProviderPlatform.instance = previousPathProvider;
    await directory.delete(recursive: true);
  });

  test("refreshes only current local rows", () async {
    final db = await files.sqliteAsyncDB;
    await db.execute('''
      INSERT INTO ${FilesDB.filesTable}
        (${FilesDB.columnLocalID}, ${FilesDB.columnUploadedFileID},
         ${FilesDB.columnCollectionID}, ${FilesDB.columnTitle},
         ${FilesDB.columnCreationTime}, ${FilesDB.columnModificationTime},
         ${FilesDB.columnLatitude}, ${FilesDB.columnLongitude},
         ${FilesDB.columnMetadataVersion}, ${FilesDB.columnPubMMdEncodedJson})
      VALUES
        ('local', -1, 1, 'photo.jpg', 100, 100, 12.3, 45.6, 3,
         '{"caption":"Keep me","w":4000,"h":3000,"mediaType":1,"mvi":42}'),
        ('local', 99, 2, 'photo.jpg', 100, 100, 12.3, 45.6, 1,
         '{"caption":"Keep me","w":4000,"h":3000}')
    ''');

    final edited = EnteFile()
      ..localID = "local"
      ..modificationTime = 200
      ..pubMmdEncodedJson = '{"w":800,"h":600}';
    await files.refreshModifiedLocalFiles([edited]);
    expect(
      await files.updateOfflineImportMetadataForLocalID(
        "local",
        processingVersion: 2,
        modificationTime: 100,
      ),
      isFalse,
    );

    final rows = await db.getAll('SELECT * FROM ${FilesDB.filesTable}');
    var local = rows.first;
    expect(
      (
        local[FilesDB.columnModificationTime],
        local[FilesDB.columnMetadataVersion],
        local[FilesDB.columnLatitude],
        local[FilesDB.columnLongitude],
      ),
      (200, -1, null, null),
    );
    expect(jsonDecode(local[FilesDB.columnPubMMdEncodedJson] as String), {
      "caption": "Keep me",
      "w": 800,
      "h": 600,
    });
    final uploaded = rows.last;
    expect(
      (
        uploaded[FilesDB.columnModificationTime],
        uploaded[FilesDB.columnMetadataVersion],
        uploaded[FilesDB.columnLatitude],
        uploaded[FilesDB.columnLongitude],
      ),
      (100, 1, 12.3, 45.6),
    );

    expect(
      await files.updateOfflineImportMetadataForLocalID(
        "local",
        processingVersion: 2,
        modificationTime: 200,
        dimensions: (width: 600, height: 800),
        mediaType: 0,
      ),
      isTrue,
    );
    await files.refreshModifiedLocalFiles([edited]);
    local = (await db.getAll(
      'SELECT * FROM ${FilesDB.filesTable} WHERE ${FilesDB.columnUploadedFileID} = -1',
    )).single;
    final metadata = jsonDecode(
      local[FilesDB.columnPubMMdEncodedJson] as String,
    );
    expect(
      (
        metadata['caption'],
        metadata['w'],
        metadata['h'],
        metadata['mediaType'],
        metadata.containsKey('mvi'),
        local[FilesDB.columnMetadataVersion],
      ),
      ("Keep me", 600, 800, 0, false, 2),
    );
  });
}

class _PathProvider extends PathProviderPlatform {
  _PathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}
