import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:locker/services/files/download/file_downloader.dart'
    as file_downloader;
import 'package:locker/services/files/offline/offline_file_storage.dart';
import 'package:locker/services/files/sync/models/file.dart';
import 'package:path/path.dart' as p;

import '../../../test_utils/configuration_test_util.dart';

void main() {
  EnteFile lockerFile({
    required int uploadedFileID,
    required String title,
    String? localPath,
  }) {
    return EnteFile()
      ..uploadedFileID = uploadedFileID
      ..title = title
      ..localPath = localPath;
  }

  Future<File> writeFile(String path, String contents) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    return file.writeAsString(contents);
  }

  group('file_downloader openFile cache identity', () {
    late Directory root;

    setUp(() async {
      root = await setupLockerConfigurationForTest('file_downloader');
    });

    tearDown(() async {
      clearLockerConfigurationTestHandlers();
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test(
      'returns ID-keyed cached decrypted copy and ignores localPath',
      () async {
        final staleLocalPath = await writeFile(
          p.join(root.path, 'old-local-copy.pdf'),
          'stale local bytes',
        );
        final file = lockerFile(
          uploadedFileID: 901,
          title: 'statement.pdf',
          localPath: staleLocalPath.path,
        );
        final cachedDecrypted = await writeFile(
          getCachedDecryptedFilePath(file),
          'current cached bytes',
        );

        final opened = await file_downloader.openFile(file, Uint8List(32));

        expect(opened, isNotNull);
        expect(opened!.path, cachedDecrypted.path);
        expect(await opened.readAsString(), 'current cached bytes');
        expect(await staleLocalPath.readAsString(), 'stale local bytes');
      },
    );

    test('isolates cached decrypted files by uploaded file ID', () async {
      final sharedLocalPath = await writeFile(
        p.join(root.path, 'shared-local.pdf'),
        'stale shared local bytes',
      );
      final firstFile = lockerFile(
        uploadedFileID: 902,
        title: 'same-name.pdf',
        localPath: sharedLocalPath.path,
      );
      final secondFile = lockerFile(
        uploadedFileID: 903,
        title: 'same-name.pdf',
        localPath: sharedLocalPath.path,
      );
      final firstCached = await writeFile(
        getCachedDecryptedFilePath(firstFile),
        'first cached bytes',
      );
      final secondCached = await writeFile(
        getCachedDecryptedFilePath(secondFile),
        'second cached bytes',
      );

      final firstOpened = await file_downloader.openFile(
        firstFile,
        Uint8List(32),
      );
      final secondOpened = await file_downloader.openFile(
        secondFile,
        Uint8List(32),
      );

      expect(firstOpened, isNotNull);
      expect(secondOpened, isNotNull);
      expect(firstOpened!.path, firstCached.path);
      expect(secondOpened!.path, secondCached.path);
      expect(await firstOpened.readAsString(), 'first cached bytes');
      expect(await secondOpened.readAsString(), 'second cached bytes');
      expect(firstOpened.path, isNot(secondOpened.path));
      expect(await sharedLocalPath.readAsString(), 'stale shared local bytes');
    });
  });
}
