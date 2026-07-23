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
      // Arrange
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
        2: PreviewInfo(
          objectId: 'obj2',
          objectSize: 1000,
        ), // Only file 2 is processed
      };

      final status = await videoPreviewService.calcStatus(files, previewIds);

      // Assert
      expect(status, closeTo(0.33, 0.01)); // 1/3 ≈ 0.33
    });

    test('should handle all files processed', () async {
      // Arrange
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

      // Assert
      expect(status, equals(1.0)); // 100% processed
    });

    test('should handle no files processed', () async {
      // Arrange
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

      final previewIds = <int, PreviewInfo>{}; // No files processed

      final status = await videoPreviewService.calcStatus(files, previewIds);

      // Assert
      expect(status, equals(0.0)); // 0% processed
    });

    test('should skip files with sv=1 from total count', () async {
      // Arrange
      final files = [
        EnteFile()
          ..uploadedFileID = 1
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(),
        EnteFile()
          ..uploadedFileID = 2
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(sv: 1), // Should be skipped
        EnteFile()
          ..uploadedFileID = 3
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(),
      ];

      final previewIds = <int, PreviewInfo>{}; // No files processed

      final status = await videoPreviewService.calcStatus(files, previewIds);

      // Assert
      expect(status, equals(0.0)); // 0% processed
    });

    test('should handle processed files with sv=1', () async {
      // Arrange
      final files = [
        EnteFile()
          ..uploadedFileID = 1
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(),
        EnteFile()
          ..uploadedFileID = 2
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(
            sv: 1,
          ), // Processed but with sv=1
        EnteFile()
          ..uploadedFileID = 3
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(),
      ];

      final previewIds = <int, PreviewInfo>{
        2: PreviewInfo(
          objectId: 'obj2',
          objectSize: 1000,
        ), // File 2 is processed
      };

      final status = await videoPreviewService.calcStatus(files, previewIds);

      // Assert
      // Logic:
      // file 2 is processed -> goes to processed set (processed = {2})
      // All files except sv=1 go to total: file 1 -> total, file 2 -> total, file 3 -> total
      // So: processed = {2}, total = {1,2,3}
      // netProcessedItems = processed.length / total.length = 1/3 ≈ 0.33
      expect(status, closeTo(0.33, 0.01));
    });

    test('should handle empty file list', () async {
      // Arrange
      final files = <EnteFile>[];
      final previewIds = <int, PreviewInfo>{};

      final status = await videoPreviewService.calcStatus(files, previewIds);

      // Assert
      expect(status, equals(1.0)); // Empty = 100% complete
    });

    test('should handle complex scenario', () async {
      // Arrange
      final files = [
        EnteFile()
          ..uploadedFileID = 1
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(), // Regular file
        EnteFile()
          ..uploadedFileID = 2
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(
            sv: 1,
          ), // Skip from total (sv=1)
        EnteFile()
          ..uploadedFileID = 3
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(), // Regular file
        EnteFile()
          ..uploadedFileID = 4
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(), // Regular file
        EnteFile()
          ..uploadedFileID = 5
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(
            sv: 1,
          ), // Skip from total (sv=1)
      ];

      final previewIds = <int, PreviewInfo>{
        1: PreviewInfo(objectId: 'obj1', objectSize: 1000), // File 1 processed
        3: PreviewInfo(objectId: 'obj3', objectSize: 1000), // File 3 processed
        5: PreviewInfo(
          objectId: 'obj5',
          objectSize: 1000,
        ), // File 5 processed (but has sv=1)
      };

      final status = await videoPreviewService.calcStatus(files, previewIds);

      // Assert
      // File 1: processed -> add to processed {1}, then add to total {1}
      // File 2: not processed, sv=1 -> skip (continue)
      // File 3: processed -> add to processed {1,3}, then add to total {1,3}
      // File 4: not processed, sv!=1 -> add to total {1,3,4}
      // File 5: processed -> add to processed {1,3,5}, then add to total {1,3,4,5}
      //
      // Result: processed = {1,3,5}, total = {1,3,4,5}
      // netProcessedItems = 3/4 = 0.75
      expect(status, equals(0.75));
    });

    test('should handle null pubMagicMetadata', () async {
      // Arrange
      final files = [
        EnteFile()
          ..uploadedFileID = 1
          ..fileType = FileType.video
          ..pubMagicMetadata = null, // null metadata
        EnteFile()
          ..uploadedFileID = 2
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(),
      ];

      final previewIds = <int, PreviewInfo>{
        1: PreviewInfo(objectId: 'obj1', objectSize: 1000),
      };

      final status = await videoPreviewService.calcStatus(files, previewIds);

      // Assert
      expect(status, equals(0.5)); // 1/2 = 0.5
    });

    test('should handle large numbers correctly', () async {
      // Arrange - Create 1000 files, 750 processed
      final files = List.generate(
        1000,
        (index) => EnteFile()
          ..uploadedFileID = index + 1
          ..fileType = FileType.video
          ..pubMagicMetadata = PubMagicMetadata(),
      );

      final previewIds = <int, PreviewInfo>{};
      // Make first 750 files processed
      for (int i = 1; i <= 750; i++) {
        previewIds[i] = PreviewInfo(objectId: 'obj$i', objectSize: 1000);
      }

      final status = await videoPreviewService.calcStatus(files, previewIds);

      // Assert
      expect(status, equals(0.75)); // 750/1000 = 0.75
    });

    test('should handle edge case - all files have sv=1', () async {
      // Arrange
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

      // Assert
      // All files have sv=1, so total set is empty, netProcessedItems should be 1.0
      expect(status, equals(1.0)); // Empty total = 100% complete
    });

    test('should handle percentage calculation precision', () async {
      // Arrange - Test precise percentage calculations
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

      // Assert
      // 2 out of 7 files processed = 2/7 ≈ 0.2857
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
