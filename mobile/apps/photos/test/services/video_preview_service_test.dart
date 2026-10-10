import 'dart:async';

import 'package:dio/dio.dart';
import "package:flutter_cache_manager/flutter_cache_manager.dart";
import 'package:flutter_test/flutter_test.dart';
import "package:photos/core/configuration.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/upload_locks_db.dart";
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import 'package:photos/models/metadata/file_magic.dart';
import 'package:photos/models/preview/playlist_data.dart';
import 'package:photos/models/preview/preview_item_status.dart';
import 'package:photos/module/upload/service/file_uploader.dart';
import "package:photos/service_locator.dart";
import "package:photos/services/ffmpeg_service.dart";
import "package:photos/services/file_magic_service.dart";
import 'package:photos/services/filedata/model/file_data.dart';
import 'package:photos/services/machine_learning/compute_controller.dart';
import 'package:photos/services/video_preview_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late VideoPreviewService videoPreviewService;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    ServiceLocator.instance.prefs = await SharedPreferences.getInstance();
    ServiceLocator.instance.enteDio = Dio();
    FileUploader.instance = _FakeFileUploader();
  });

  setUp(() {
    videoPreviewService = VideoPreviewService(
      _FakeConfiguration(),
      _FakeServiceLocator(),
      _FakeFilesDB(),
      _FakeUploadLocksDB(),
      _FakeFileMagicService(),
      _FakeFfmpegService(),
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

  test('export pauses scheduling without clearing pending previews', () async {
    final compute = _FakeComputeController();
    final service = _ControlledPreviewService(compute);
    final file = EnteFile()..uploadedFileID = 42;
    service.uploadingFileId = 42;
    await service.addToManualQueue(file, 'create');

    await service.pauseForExport();
    expect(compute.computeBlocked, isTrue);
    expect(compute.releases, 0);
    expect(service.getProcessingStatus(42), PreviewItemStatus.inQueue);
    expect(service.uploadingFileId, 42);

    service.resumeAfterExport();
    expect(compute.computeBlocked, isFalse);
    expect(service.resumeRequests, 1);
  });

  test(
    'stopped preparation cannot repopulate a resumed preview queue',
    () async {
      final compute = _FakeComputeController();
      final service = _ControlledPreviewService(compute);
      final file = EnteFile()
        ..uploadedFileID = 42
        ..fileType = FileType.video;
      service.uploadingFileId = 42;
      await service.addToManualQueue(file, 'create');
      service.uploadingFileId = -1;

      final preparation = service.chunkAndUploadVideo(null, file);
      await service.playlistRequested.future;
      service.stop('export');
      service.resumeAfterExport();
      service.playlist.complete(null);
      await preparation;

      expect(service.getProcessingStatus(42), isNull);
      expect(service.fileQueue, isEmpty);
      expect(compute.releases, 1);
    },
  );
}

class _FakeServiceLocator extends Fake implements ServiceLocator {}

class _FakeConfiguration extends Fake implements Configuration {}

class _FakeFilesDB extends Fake implements FilesDB {}

class _FakeUploadLocksDB extends Fake implements UploadLocksDB {
  @override
  Future<bool> isInStreamQueue(int fileID) async => false;

  @override
  Future<void> addToStreamQueue(int fileID, String queueType) async {}

  @override
  Future<Map<int, String>> getStreamQueue() async => {};
}

class _FakeFileMagicService extends Fake implements FileMagicService {}

class _FakeFfmpegService extends Fake implements FfmpegService {}

class _FakeDefaultCacheManager extends Fake implements DefaultCacheManager {}

class _FakeCacheManager extends Fake implements CacheManager {}

class _FakeFileUploader extends Fake implements FileUploader {
  @override
  bool get isUploading => false;
}

class _FakeComputeController extends Fake implements ComputeController {
  @override
  bool computeBlocked = false;
  int releases = 0;

  @override
  ComputeRunState get computeState => ComputeRunState.generatingStream;

  @override
  bool get isDeviceHealthy => true;

  @override
  void blockCompute({required String blocker}) => computeBlocked = true;

  @override
  void unblockCompute({required String blocker}) => computeBlocked = false;

  @override
  void releaseCompute({bool ml = false, bool stream = false}) => releases++;
}

class _ControlledPreviewService extends VideoPreviewService {
  _ControlledPreviewService(ComputeController compute)
    : super(
        _FakeConfiguration(),
        _FakeServiceLocator(),
        _FakeFilesDB(),
        _FakeUploadLocksDB(),
        _FakeFileMagicService(),
        _FakeFfmpegService(),
        _FakeDefaultCacheManager(),
        _FakeCacheManager(),
        compute: compute,
      );

  final playlistRequested = Completer<void>();
  final playlist = Completer<PlaylistData?>();
  int resumeRequests = 0;

  @override
  bool get isVideoStreamingEnabled => true;

  @override
  Future<PlaylistData?> getPlaylist(EnteFile file) {
    playlistRequested.complete();
    return playlist.future;
  }

  @override
  void queueFiles({
    Duration duration = const Duration(seconds: 5),
    bool isManual = false,
    bool forceProcess = false,
  }) => resumeRequests++;
}
