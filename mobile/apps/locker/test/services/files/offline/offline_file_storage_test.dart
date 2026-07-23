import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locker/services/configuration.dart';
import 'package:locker/services/files/offline/offline_file_storage.dart';
import 'package:locker/services/files/sync/models/file.dart';
import 'package:path/path.dart' as p;

import '../../../test_utils/configuration_test_util.dart';

void main() {
  EnteFile lockerFile(int uploadedFileID, {String title = 'document.pdf'}) {
    return EnteFile()
      ..uploadedFileID = uploadedFileID
      ..title = title;
  }

  Future<File> writeFile(String path, String contents) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    return file.writeAsString(contents);
  }

  Future<Directory> createHandoff(
    int uploadedFileID,
    String timestamp, {
    String fileName = 'document.pdf',
  }) async {
    final directory = Directory(
      p.join(
        getOpenHandoffDirectoryPath(),
        uploadedFileID.toString(),
        timestamp,
      ),
    );
    await directory.create(recursive: true);
    await writeFile(p.join(directory.path, fileName), timestamp);
    return directory;
  }

  Future<void> makeOld(File file) async {
    await file.setLastModified(
      DateTime.now().subtract(const Duration(minutes: 5)),
    );
  }

  group('OfflineFileStorage', () {
    late Directory root;

    setUp(() async {
      root = await setupLockerConfigurationForTest('offline_storage');
    });

    tearDown(() async {
      clearLockerConfigurationTestHandlers();
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('removes only the selected file ID from owned storage', () async {
      final firstFile = lockerFile(123, title: 'first.pdf');
      final secondFile = lockerFile(456, title: 'second.png');
      final firstOffline = await writeFile(
        await getOfflineEncryptedFilePath(firstFile),
        'offline 123',
      );
      final secondOffline = await writeFile(
        await getOfflineEncryptedFilePath(secondFile),
        'offline 456',
      );
      final malformedOffline = await writeFile(
        p.join(firstOffline.parent.path, 'not-a-file-id.encrypted'),
        'malformed',
      );
      final firstCachedEncrypted = await writeFile(
        getCachedEncryptedFilePath(firstFile),
        'cached encrypted 123',
      );
      final firstCachedDecrypted = await writeFile(
        getCachedDecryptedFilePath(firstFile),
        'cached decrypted 123',
      );
      final malformedCachedDecrypted = await writeFile(
        p.join(Configuration.instance.getCacheDirectory(), '123.decrypted_bak'),
        'malformed decrypted',
      );
      final secondCachedEncrypted = await writeFile(
        getCachedEncryptedFilePath(secondFile),
        'cached encrypted 456',
      );
      final secondCachedDecrypted = await writeFile(
        getCachedDecryptedFilePath(secondFile),
        'cached decrypted 456',
      );
      final firstHandoff = await createHandoff(123, '100');
      final secondHandoff = await createHandoff(456, '100');
      final nonIdHandoff = Directory(
        p.join(getOpenHandoffDirectoryPath(), 'not-an-id', '100'),
      );
      await nonIdHandoff.create(recursive: true);
      final unrelatedCacheFile = await writeFile(
        p.join(Configuration.instance.getCacheDirectory(), 'keep.me'),
        'unrelated',
      );

      await removeOfflineFileCopiesFromDisk([123]);

      expect(await firstOffline.exists(), isFalse);
      expect(await firstCachedEncrypted.exists(), isFalse);
      expect(await firstCachedDecrypted.exists(), isFalse);
      expect(await firstHandoff.exists(), isFalse);
      expect(await malformedCachedDecrypted.exists(), isTrue);
      expect(await secondOffline.exists(), isTrue);
      expect(await secondCachedEncrypted.exists(), isTrue);
      expect(await secondCachedDecrypted.exists(), isTrue);
      expect(await secondHandoff.exists(), isTrue);
      expect(await malformedOffline.exists(), isTrue);
      expect(await nonIdHandoff.exists(), isTrue);
      expect(await unrelatedCacheFile.exists(), isTrue);
    });

    test(
      'can remove offline encrypted blobs while preserving working copies',
      () async {
        final file = lockerFile(123, title: 'document.pdf');
        final offline = await writeFile(
          await getOfflineEncryptedFilePath(file),
          'offline 123',
        );
        final cachedEncrypted = await writeFile(
          getCachedEncryptedFilePath(file),
          'cached encrypted 123',
        );
        final cachedDecrypted = await writeFile(
          getCachedDecryptedFilePath(file),
          'cached decrypted 123',
        );
        final handoff = await createHandoff(123, '100');

        await removeOfflineFileCopiesFromDisk([
          123,
        ], removeWorkingCopies: false);

        expect(await offline.exists(), isFalse);
        expect(await cachedEncrypted.exists(), isTrue);
        expect(await cachedDecrypted.exists(), isTrue);
        expect(await handoff.exists(), isTrue);
      },
    );

    test(
      'clears owned offline cache while preserving unrelated cache files',
      () async {
        final firstFile = lockerFile(123, title: 'first.pdf');
        final secondFile = lockerFile(456, title: 'second.png');
        final firstOffline = await writeFile(
          await getOfflineEncryptedFilePath(firstFile),
          'offline 123',
        );
        final secondOffline = await writeFile(
          await getOfflineEncryptedFilePath(secondFile),
          'offline 456',
        );
        final malformedOffline = await writeFile(
          p.join(firstOffline.parent.path, 'not-a-file-id.encrypted'),
          'malformed offline',
        );
        final firstCachedEncrypted = await writeFile(
          getCachedEncryptedFilePath(firstFile),
          'cached encrypted 123',
        );
        final firstCachedDecrypted = await writeFile(
          getCachedDecryptedFilePath(firstFile),
          'cached decrypted 123',
        );
        final secondCachedEncrypted = await writeFile(
          getCachedEncryptedFilePath(secondFile),
          'cached encrypted 456',
        );
        final secondCachedDecrypted = await writeFile(
          getCachedDecryptedFilePath(secondFile),
          'cached decrypted 456',
        );
        final firstHandoff = await createHandoff(123, '100');
        final secondHandoff = await createHandoff(456, '100');
        final nonIdHandoff = Directory(
          p.join(getOpenHandoffDirectoryPath(), 'not-an-id', '100'),
        );
        await nonIdHandoff.create(recursive: true);
        await writeFile(p.join(nonIdHandoff.path, 'document.pdf'), 'non id');
        final rootHandoffFile = await writeFile(
          p.join(getOpenHandoffDirectoryPath(), 'root-handoff.tmp'),
          'root handoff',
        );
        final unrelatedCacheFile = await writeFile(
          p.join(Configuration.instance.getCacheDirectory(), 'keep.me'),
          'unrelated',
        );

        await clearAllOfflineFileCopies();

        expect(await firstOffline.exists(), isFalse);
        expect(await secondOffline.exists(), isFalse);
        expect(await malformedOffline.exists(), isFalse);
        expect(await firstCachedEncrypted.exists(), isFalse);
        expect(await firstCachedDecrypted.exists(), isFalse);
        expect(await secondCachedEncrypted.exists(), isFalse);
        expect(await secondCachedDecrypted.exists(), isFalse);
        expect(await firstHandoff.exists(), isFalse);
        expect(await secondHandoff.exists(), isFalse);
        expect(await nonIdHandoff.exists(), isFalse);
        expect(await rootHandoffFile.exists(), isFalse);
        expect(await unrelatedCacheFile.exists(), isTrue);
      },
    );

    test('stale cache cleanup is age gated and ID pattern scoped', () async {
      final oldFile = lockerFile(123, title: 'old.pdf');
      final freshFile = lockerFile(456, title: 'fresh.pdf');
      final oldOfflineEncrypted = await writeFile(
        await getOfflineEncryptedFilePath(oldFile),
        'offline source',
      );
      final oldCachedEncrypted = await writeFile(
        getCachedEncryptedFilePath(oldFile),
        'old encrypted',
      );
      final oldCachedDecrypted = await writeFile(
        getCachedDecryptedFilePath(oldFile),
        'old decrypted',
      );
      final freshCachedEncrypted = await writeFile(
        getCachedEncryptedFilePath(freshFile),
        'fresh encrypted',
      );
      final freshCachedDecrypted = await writeFile(
        getCachedDecryptedFilePath(freshFile),
        'fresh decrypted',
      );
      final staleUnrelatedCacheFile = await writeFile(
        p.join(Configuration.instance.getCacheDirectory(), 'keep.me'),
        'unrelated',
      );
      final staleMalformedCacheFile = await writeFile(
        p.join(Configuration.instance.getCacheDirectory(), '123.encrypted.bak'),
        'malformed',
      );
      final staleMalformedDecryptedCacheFile = await writeFile(
        p.join(Configuration.instance.getCacheDirectory(), '123.decrypted_bak'),
        'malformed decrypted',
      );
      await makeOld(oldOfflineEncrypted);
      await makeOld(oldCachedEncrypted);
      await makeOld(oldCachedDecrypted);
      await makeOld(staleUnrelatedCacheFile);
      await makeOld(staleMalformedCacheFile);
      await makeOld(staleMalformedDecryptedCacheFile);

      await cleanupStaleOfflineFileCopies(
        olderThan: const Duration(minutes: 1),
      );

      expect(await oldOfflineEncrypted.exists(), isTrue);
      expect(await oldCachedEncrypted.exists(), isFalse);
      expect(await oldCachedDecrypted.exists(), isFalse);
      expect(await freshCachedEncrypted.exists(), isTrue);
      expect(await freshCachedDecrypted.exists(), isTrue);
      expect(await staleUnrelatedCacheFile.exists(), isTrue);
      expect(await staleMalformedCacheFile.exists(), isTrue);
      expect(await staleMalformedDecryptedCacheFile.exists(), isTrue);
    });

    test('ages timestamp children instead of file ID parent', () async {
      final cacheDirectory = Configuration.instance.getCacheDirectory();
      final oldHandoff = Directory(
        p.join(cacheDirectory, 'open_handoff', '123', '100'),
      );
      final freshHandoff = Directory(
        p.join(cacheDirectory, 'open_handoff', '123', '200'),
      );
      final staleOnlyHandoff = Directory(
        p.join(cacheDirectory, 'open_handoff', '456', '100'),
      );
      final unrelatedCacheFile = File(p.join(cacheDirectory, 'keep.me'));
      await oldHandoff.create(recursive: true);
      await staleOnlyHandoff.create(recursive: true);
      await File(p.join(oldHandoff.path, 'document.pdf')).writeAsString('old');
      await File(
        p.join(staleOnlyHandoff.path, 'document.pdf'),
      ).writeAsString('stale');
      final staleRootHandoffFile = await writeFile(
        p.join(cacheDirectory, 'open_handoff', 'stale-root.tmp'),
        'stale root',
      );
      await unrelatedCacheFile.writeAsString('unrelated');

      await Future<void>.delayed(const Duration(seconds: 2));
      await freshHandoff.create(recursive: true);
      await File(
        p.join(freshHandoff.path, 'document.pdf'),
      ).writeAsString('fresh');
      final freshRootHandoffFile = await writeFile(
        p.join(cacheDirectory, 'open_handoff', 'fresh-root.tmp'),
        'fresh root',
      );

      await cleanupStaleOfflineFileCopies(
        olderThan: const Duration(seconds: 1),
      );

      expect(await oldHandoff.exists(), isFalse);
      expect(await freshHandoff.exists(), isTrue);
      expect(await staleRootHandoffFile.exists(), isFalse);
      expect(await freshRootHandoffFile.exists(), isTrue);
      expect(
        await Directory(p.join(cacheDirectory, 'open_handoff', '123')).exists(),
        isTrue,
      );
      expect(await staleOnlyHandoff.exists(), isFalse);
      expect(
        await Directory(p.join(cacheDirectory, 'open_handoff', '456')).exists(),
        isFalse,
      );
      expect(await unrelatedCacheFile.exists(), isTrue);
    });
  });
}
