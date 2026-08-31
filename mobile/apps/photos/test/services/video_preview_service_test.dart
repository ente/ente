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

  group('calcStatus', () {
    test('excludes legacy files unless they already have previews', () async {
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
