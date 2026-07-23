import 'dart:io';

import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('deleteFileSystemEntityIfPresent', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'ente_pure_utils_directory_content_util_test_',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('deletes an existing file', () async {
      final file = File(p.join(tempDir.path, 'file.txt'));
      await file.writeAsString('content');

      final deleted = await deleteFileSystemEntityIfPresent(file);

      expect(deleted, isTrue);
      expect(await file.exists(), isFalse);
    });

    test('returns false when the path is already missing', () async {
      final missingFile = File(p.join(tempDir.path, 'missing.txt'));

      final deleted = await deleteFileSystemEntityIfPresent(missingFile);

      expect(deleted, isFalse);
    });

    test('identifies missing path file system errors', () async {
      final missingFile = File(p.join(tempDir.path, 'missing.txt'));

      try {
        await missingFile.delete();
        fail('delete should fail for a missing file');
      } on FileSystemException catch (e) {
        expect(isFileSystemPathMissing(e), isTrue);
      }
    });

    test('deletes a directory recursively', () async {
      final directory = Directory(p.join(tempDir.path, 'nested'));
      await directory.create();
      await File(p.join(directory.path, 'file.txt')).writeAsString('content');

      final deleted = await deleteFileSystemEntityIfPresent(
        directory,
        recursive: true,
      );

      expect(deleted, isTrue);
      expect(await directory.exists(), isFalse);
    });
  });

  group('deleteDirectoryContents', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'ente_pure_utils_directory_content_util_test_',
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('deletes files and directories while preserving the root', () async {
      await File(p.join(tempDir.path, 'file.txt')).writeAsString('content');
      final directory = Directory(p.join(tempDir.path, 'nested'));
      await directory.create();
      await File(p.join(directory.path, 'file.txt')).writeAsString('content');

      await deleteDirectoryContents(tempDir.path);

      expect(await tempDir.exists(), isTrue);
      expect(await tempDir.list().toList(), isEmpty);
    });

    test('ignores a missing root directory', () async {
      final missingDirectory = Directory(p.join(tempDir.path, 'missing'));

      await deleteDirectoryContents(missingDirectory.path);

      expect(await missingDirectory.exists(), isFalse);
    });
  });
}
