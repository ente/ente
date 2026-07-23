import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locker/services/configuration.dart';
import 'package:locker/services/files/offline/offline_file_storage.dart';
import 'package:locker/services/files/sync/models/file.dart';
import 'package:locker/utils/file_util.dart';
import 'package:path/path.dart' as p;

import '../test_utils/configuration_test_util.dart';

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

  String cacheRelativePath(File file) {
    return p.relative(
      file.path,
      from: Configuration.instance.getCacheDirectory(),
    );
  }

  group('FileUtil handoff preparation', () {
    late Directory root;

    setUp(() async {
      root = await setupLockerConfigurationForTest('file_util');
    });

    tearDown(() async {
      clearLockerConfigurationTestHandlers();
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('creates a fresh open_handoff copy using uploaded file ID', () async {
      final source = File(p.join(root.path, 'source.bin'));
      await source.writeAsString('current file bytes');
      final file = lockerFile(uploadedFileID: 123, title: 'original.pdf');

      final handoffFile = await FileUtil.prepareOpenFileForTest(
        source,
        displayName: null,
        lockerFile: file,
      );

      expect(handoffFile.path, isNot(source.path));
      expect(await handoffFile.readAsString(), 'current file bytes');
      expect(await source.exists(), isTrue);
      expect(
        cacheRelativePath(handoffFile),
        startsWith(p.join('open_handoff', '123')),
      );
      expect(p.basename(handoffFile.path), 'file-123.pdf');
    });

    test('uses UI display name with metadata-derived extension', () async {
      final source = File(p.join(root.path, 'source.bin'));
      await source.writeAsString('renamed file bytes');
      final file = lockerFile(uploadedFileID: 456, title: 'passport.png');

      final handoffFile = await FileUtil.prepareOpenFileForTest(
        source,
        displayName: 'Front side',
        lockerFile: file,
      );

      expect(p.basename(handoffFile.path), 'Front side.png');
      expect(await handoffFile.readAsString(), 'renamed file bytes');
      expect(
        cacheRelativePath(handoffFile),
        startsWith(p.join('open_handoff', '456')),
      );
    });

    test(
      'creates distinct handoff paths for repeated same-file opens',
      () async {
        final source = File(p.join(root.path, 'source.bin'));
        await source.writeAsString('first version');
        final file = lockerFile(uploadedFileID: 234, title: 'invoice.pdf');

        final firstHandoff = await FileUtil.prepareOpenFileForTest(
          source,
          displayName: 'Invoice',
          lockerFile: file,
        );

        await source.writeAsString('second version');
        await Future<void>.delayed(const Duration(milliseconds: 1));

        final secondHandoff = await FileUtil.prepareOpenFileForTest(
          source,
          displayName: 'Invoice',
          lockerFile: file,
        );

        expect(secondHandoff.path, isNot(firstHandoff.path));
        expect(
          p.dirname(secondHandoff.path),
          isNot(p.dirname(firstHandoff.path)),
        );
        expect(p.basename(firstHandoff.path), 'Invoice.pdf');
        expect(p.basename(secondHandoff.path), 'Invoice.pdf');
        expect(await firstHandoff.readAsString(), 'first version');
        expect(await secondHandoff.readAsString(), 'second version');
        expect(await source.readAsString(), 'second version');
      },
    );

    test('ignores stale localPath when preparing the open handoff', () async {
      final source = File(p.join(root.path, 'current-cache.bin'));
      final staleLocalPath = File(p.join(root.path, 'old-local-copy.docx'));
      await source.writeAsString('current cache bytes');
      await staleLocalPath.writeAsString('stale local bytes');
      final file = lockerFile(
        uploadedFileID: 321,
        title: 'locker-copy.pdf',
        localPath: staleLocalPath.path,
      );

      final handoffFile = await FileUtil.prepareOpenFileForTest(
        source,
        displayName: null,
        lockerFile: file,
      );

      expect(await handoffFile.readAsString(), 'current cache bytes');
      expect(await staleLocalPath.readAsString(), 'stale local bytes');
      expect(cacheRelativePath(handoffFile), startsWith('open_handoff'));
      expect(
        cacheRelativePath(handoffFile),
        startsWith(p.join('open_handoff', '321')),
      );
      expect(p.basename(handoffFile.path), 'file-321.pdf');
      expect(handoffFile.path, isNot(staleLocalPath.path));
    });

    test(
      'partitions handoff copies by uploaded file ID, not source path',
      () async {
        final source = File(p.join(root.path, 'shared-source.bin'));
        final staleLocalPath = File(p.join(root.path, 'same-stale-local.txt'));
        await source.writeAsString('shared source bytes');
        await staleLocalPath.writeAsString('shared stale bytes');
        final firstFile = lockerFile(
          uploadedFileID: 111,
          title: 'first.pdf',
          localPath: staleLocalPath.path,
        );
        final secondFile = lockerFile(
          uploadedFileID: 222,
          title: 'second.pdf',
          localPath: staleLocalPath.path,
        );

        final firstHandoff = await FileUtil.prepareOpenFileForTest(
          source,
          displayName: 'Document',
          lockerFile: firstFile,
        );
        final secondHandoff = await FileUtil.prepareOpenFileForTest(
          source,
          displayName: 'Document',
          lockerFile: secondFile,
        );

        expect(
          cacheRelativePath(firstHandoff),
          startsWith(p.join('open_handoff', '111')),
        );
        expect(
          cacheRelativePath(secondHandoff),
          startsWith(p.join('open_handoff', '222')),
        );
        expect(await firstHandoff.readAsString(), 'shared source bytes');
        expect(await secondHandoff.readAsString(), 'shared source bytes');
        expect(await staleLocalPath.readAsString(), 'shared stale bytes');
      },
    );

    test(
      'replaces stale display extension with Locker metadata extension',
      () async {
        final source = File(p.join(root.path, 'front.tmp'));
        await source.writeAsString('front bytes');
        final file = lockerFile(uploadedFileID: 654, title: 'passport.png');

        final handoffFile = await FileUtil.prepareOpenFileForTest(
          source,
          displayName: 'Front side.jpg',
          lockerFile: file,
        );

        expect(p.basename(handoffFile.path), 'Front side.png');
        expect(await handoffFile.readAsString(), 'front bytes');
      },
    );

    test(
      'keeps display extension when it already matches metadata extension',
      () async {
        final source = File(p.join(root.path, 'invoice.tmp'));
        await source.writeAsString('invoice bytes');
        final file = lockerFile(uploadedFileID: 655, title: 'invoice.pdf');

        final handoffFile = await FileUtil.prepareOpenFileForTest(
          source,
          displayName: 'Invoice.PDF',
          lockerFile: file,
        );

        expect(p.basename(handoffFile.path), 'Invoice.PDF');
        expect(await handoffFile.readAsString(), 'invoice bytes');
      },
    );

    test(
      'falls back to source extension when metadata has no extension',
      () async {
        final source = File(p.join(root.path, 'current-cache.bin'));
        await source.writeAsString('source extension bytes');
        final file = lockerFile(uploadedFileID: 656, title: 'untitled');

        final handoffFile = await FileUtil.prepareOpenFileForTest(
          source,
          displayName: 'Visible name',
          lockerFile: file,
        );

        expect(p.basename(handoffFile.path), 'Visible name.bin');
        expect(await handoffFile.readAsString(), 'source extension bytes');
      },
    );

    test(
      'falls back to display extension when metadata and source lack one',
      () async {
        final source = File(p.join(root.path, 'current-cache'));
        await source.writeAsString('display extension bytes');
        final file = lockerFile(uploadedFileID: 657, title: 'untitled');

        final handoffFile = await FileUtil.prepareOpenFileForTest(
          source,
          displayName: 'Visible name.pdf',
          lockerFile: file,
        );

        expect(p.basename(handoffFile.path), 'Visible name.pdf');
        expect(await handoffFile.readAsString(), 'display extension bytes');
      },
    );

    test(
      'does not use internal decrypted cache suffix as handoff extension',
      () async {
        final file = lockerFile(uploadedFileID: 658, title: 'untitled');
        final source = File(getCachedDecryptedFilePath(file));
        await source.writeAsString('cached decrypted bytes');

        final handoffFile = await FileUtil.prepareOpenFileForTest(
          source,
          displayName: 'Visible name.pdf',
          lockerFile: file,
        );

        expect(p.basename(source.path), '658.decrypted');
        expect(p.basename(handoffFile.path), 'Visible name.pdf');
        expect(await handoffFile.readAsString(), 'cached decrypted bytes');
      },
    );

    test('sanitizes display names before creating the handoff copy', () async {
      final source = File(p.join(root.path, 'source.bin'));
      await source.writeAsString('safe bytes');
      final file = lockerFile(uploadedFileID: 987, title: 'document.pdf');

      final handoffFile = await FileUtil.prepareOpenFileForTest(
        source,
        displayName: 'bad:*?"<>|name',
        lockerFile: file,
      );

      final launchName = p.basename(handoffFile.path);
      expect(launchName, endsWith('.pdf'));
      expect(launchName, isNot(contains(RegExp(r'[\\/:*?"<>|]'))));
      expect(await handoffFile.readAsString(), 'safe bytes');
    });

    test('fails closed when handoff copy cannot be created', () async {
      final missingSource = File(p.join(root.path, 'missing.pdf'));
      final file = lockerFile(uploadedFileID: 789, title: 'missing.pdf');

      await expectLater(
        FileUtil.prepareOpenFileForTest(
          missingSource,
          displayName: 'Missing',
          lockerFile: file,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
