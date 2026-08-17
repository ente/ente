import "package:flutter_cache_manager/flutter_cache_manager.dart";
import 'package:flutter_test/flutter_test.dart';
import "package:photos/core/configuration.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/upload_locks_db.dart";
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import 'package:photos/models/metadata/file_magic.dart';
import "package:photos/service_locator.dart";
import "package:photos/services/file_magic_service.dart";
import 'package:photos/services/filedata/model/file_data.dart';
import "package:photos/services/isolated_ffmpeg_service.dart";
import 'package:photos/services/video_preview_service.dart';

void main() {
  late VideoPreviewService videoPreviewService;

  setUp(() {
    videoPreviewService = VideoPreviewService(
      _FakeConfiguration(),
      _FakeServiceLocator(),
      _FakeFilesDB(),
      _FakeUploadLocksDB(),
      _FakeFileMagicService(),
      _FakeIsolatedFfmpegService(),
      _FakeDefaultCacheManager(),
      _FakeCacheManager(),
    );
  });

  group('calcStatus Logic Tests', () {
    test('should handle mixed processed and unprocessed files', () async {
      final files = [
        EnteFile()
          ..uploadedFileID = 1
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(),
        EnteFile()
          ..uploadedFileID = 2
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(),
        EnteFile()
          ..uploadedFileID = 3
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(),
      ];

      final previewIds = <int, PreviewInfo>{
        2: PreviewInfo(objectId: 'obj2', objectSize: 1000),
      };

      final status = await videoPreviewService.calcStatus(files, previewIds);

      expect(status, closeTo(0.33, 0.01));
    });

    test('should handle all files processed', () async {
      final files = [
        EnteFile()
          ..uploadedFileID = 1
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(),
        EnteFile()
          ..uploadedFileID = 2
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(),
      ];

      final previewIds = <int, PreviewInfo>{
        1: PreviewInfo(objectId: 'obj1', objectSize: 1000),
        2: PreviewInfo(objectId: 'obj2', objectSize: 1000),
      };

      final status = await videoPreviewService.calcStatus(files, previewIds);

      expect(status, equals(1.0));
    });

    test('should handle no files processed', () async {
      final files = [
        EnteFile()
          ..uploadedFileID = 1
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(),
        EnteFile()
          ..uploadedFileID = 2
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(),
      ];

      final previewIds = <int, PreviewInfo>{};

      final status = await videoPreviewService.calcStatus(files, previewIds);

      expect(status, equals(0.0));
    });

    test('should skip files with sv=1 from total count', () async {
      final files = [
        EnteFile()
          ..uploadedFileID = 1
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(),
        EnteFile()
          ..uploadedFileID = 2
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(sv: 1),
        EnteFile()
          ..uploadedFileID = 3
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(),
      ];

      final previewIds = <int, PreviewInfo>{};

      final status = await videoPreviewService.calcStatus(files, previewIds);

      expect(status, equals(0.0));
    });

    test('should handle processed files with sv=1', () async {
      final files = [
        EnteFile()
          ..uploadedFileID = 1
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(),
        EnteFile()
          ..uploadedFileID = 2
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(sv: 1),
        EnteFile()
          ..uploadedFileID = 3
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(),
      ];

      final previewIds = <int, PreviewInfo>{
        2: PreviewInfo(objectId: 'obj2', objectSize: 1000),
      };

      final status = await videoPreviewService.calcStatus(files, previewIds);

      expect(status, closeTo(0.33, 0.01));
    });

    test('should handle empty file list', () async {
      final files = <EnteFile>[];
      final previewIds = <int, PreviewInfo>{};

      final status = await videoPreviewService.calcStatus(files, previewIds);

      expect(status, equals(1.0));
    });

    test('should handle complex scenario', () async {
      final files = [
        EnteFile()
          ..uploadedFileID = 1
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(),
        EnteFile()
          ..uploadedFileID = 2
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(sv: 1),
        EnteFile()
          ..uploadedFileID = 3
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(),
        EnteFile()
          ..uploadedFileID = 4
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(),
        EnteFile()
          ..uploadedFileID = 5
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(sv: 1),
      ];

      final previewIds = <int, PreviewInfo>{
        1: PreviewInfo(objectId: 'obj1', objectSize: 1000),
        3: PreviewInfo(objectId: 'obj3', objectSize: 1000),
        5: PreviewInfo(objectId: 'obj5', objectSize: 1000),
      };

      final status = await videoPreviewService.calcStatus(files, previewIds);

      expect(status, equals(0.75));
    });

    test('should handle null pubMagicMetadata', () async {
      final files = [
        EnteFile()
          ..uploadedFileID = 1
          ..fileType = FileType.video
          ..pubMagicMetadata = null,
        EnteFile()
          ..uploadedFileID = 2
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(),
      ];

      final previewIds = <int, PreviewInfo>{
        1: PreviewInfo(objectId: 'obj1', objectSize: 1000),
      };

      final status = await videoPreviewService.calcStatus(files, previewIds);

      expect(status, equals(0.5));
    });

    test('should handle large numbers correctly', () async {
      final files = List.generate(
        1000,
        (index) => EnteFile()
          ..uploadedFileID = index + 1
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(),
      );

      final previewIds = <int, PreviewInfo>{};
      for (int i = 1; i <= 750; i++) {
        previewIds[i] = PreviewInfo(objectId: 'obj$i', objectSize: 1000);
      }

      final status = await videoPreviewService.calcStatus(files, previewIds);

      expect(status, equals(0.75));
    });

    test('should handle edge case - all files have sv=1', () async {
      final files = [
        EnteFile()
          ..uploadedFileID = 1
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(sv: 1),
        EnteFile()
          ..uploadedFileID = 2
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(sv: 1),
      ];

      final previewIds = <int, PreviewInfo>{
        1: PreviewInfo(objectId: 'obj1', objectSize: 1000),
        2: PreviewInfo(objectId: 'obj2', objectSize: 1000),
      };

      final status = await videoPreviewService.calcStatus(files, previewIds);

      expect(status, equals(1.0));
    });

    test('should handle percentage calculation precision', () async {
      final files = List.generate(
        7,
        (index) => EnteFile()
          ..uploadedFileID = index + 1
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(),
      );

      final previewIds = <int, PreviewInfo>{
        1: PreviewInfo(objectId: 'obj1', objectSize: 1000),
        2: PreviewInfo(objectId: 'obj2', objectSize: 1000),
      };

      final status = await videoPreviewService.calcStatus(files, previewIds);

      expect(status, closeTo(0.2857, 0.0001));
    });
  });
}

class _FakeServiceLocator extends Fake implements ServiceLocator {}

class _FakeConfiguration extends Fake implements Configuration {}

class _FakeFilesDB extends Fake implements FilesDB {}

class _FakeUploadLocksDB extends Fake implements UploadLocksDB {}

class _FakeFileMagicService extends Fake implements FileMagicService {}

class _FakeIsolatedFfmpegService extends Fake
    implements IsolatedFfmpegService {}

class _FakeDefaultCacheManager extends Fake implements DefaultCacheManager {}

class _FakeCacheManager extends Fake implements CacheManager {}
