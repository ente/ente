import "dart:async";
import "dart:collection";
import "dart:convert";
import "dart:io";

import "package:collection/collection.dart";
import "package:dio/dio.dart";
import "package:encrypt/encrypt.dart" as enc;
import "package:ente_strings/ente_strings.dart";
import "package:ffmpeg/ffmpeg.dart" as ffmpeg;
import "package:flutter/foundation.dart";
import "package:flutter/widgets.dart";
import "package:flutter_cache_manager/flutter_cache_manager.dart";
import "package:logging/logging.dart";
import "package:path_provider/path_provider.dart";
import "package:photos/core/cache/video_cache_manager.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/upload_locks_db.dart";
import "package:photos/events/device_health_changed_event.dart";
import "package:photos/events/sync_status_update_event.dart";
import "package:photos/events/video_preview_state_changed_event.dart";
import "package:photos/events/video_streaming_changed.dart";
import "package:photos/gateways/files/file_data_gateway.dart";
import "package:photos/models/base/id.dart";
import "package:photos/models/ffmpeg/ffprobe_props.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/models/preview/playlist_data.dart";
import "package:photos/models/preview/preview_item.dart";
import "package:photos/models/preview/preview_item_status.dart";
import "package:photos/module/download/file.dart";
import "package:photos/module/metadata/video.dart";
import "package:photos/module/upload/service/file_uploader.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/ffmpeg_service.dart";
import "package:photos/services/file_magic_service.dart";
import "package:photos/services/filedata/model/file_data.dart";
import "package:photos/services/filedata/preview_upload.dart";
import "package:photos/services/machine_learning/compute_controller.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/utils/file_key.dart";
import "package:photos/utils/gzip.dart";
import "package:photos/utils/hls_playlist.dart";
import "package:photos/utils/network_util.dart";

const _maxRetryCount = 3;
const _missingVideoStreamError = "No video stream found in FFprobe metadata";

class VideoPreviewService {
  final _logger = Logger("VideoPreviewService");
  final LinkedHashMap<int, PreviewItem> _items = LinkedHashMap();
  LinkedHashMap<int, EnteFile> fileQueue = LinkedHashMap();
  final int _maxPreviewSizeLimitForCache = 50 * 1024 * 1024; // 50 MB
  Set<int>? _failureFiles;

  bool get _hasQueuedFile => fileQueue.isNotEmpty;

  VideoPreviewService._privateConstructor()
    : serviceLocator = ServiceLocator.instance,
      filesDB = FilesDB.instance,
      uploadLocksDB = UploadLocksDB.instance,
      ffmpegService = FfmpegService.instance,
      fileMagicService = FileMagicService.instance,
      cacheManager = DefaultCacheManager(),
      videoCacheManager = VideoCacheManager.instance,
      _computeController = null,
      config = Configuration.instance {
    _registerStopSafelyListeners();
  }

  void _registerStopSafelyListeners() {
    Bus.instance.on<SyncStatusUpdate>().listen((event) {
      if (event.status == SyncStatus.preparingForUpload) {
        stopSafely("sync").ignore();
      }
    });

    Bus.instance.on<DeviceHealthChangedEvent>().listen((event) {
      if (!event.isHealthy) {
        stopSafely("device unhealthy").ignore();
      }
    });
  }

  VideoPreviewService(
    this.config,
    this.serviceLocator,
    this.filesDB,
    this.uploadLocksDB,
    this.fileMagicService,
    this.ffmpegService,
    this.cacheManager,
    this.videoCacheManager, {
    ComputeController? compute,
  }) : _computeController = compute;

  static final VideoPreviewService instance =
      VideoPreviewService._privateConstructor();

  int uploadingFileId = -1;
  CancelToken? _streamingCancelToken;
  FfmpegJob? _currentFfmpegJob;

  final Configuration config;
  final ServiceLocator serviceLocator;
  final FilesDB filesDB;
  final UploadLocksDB uploadLocksDB;
  final FileMagicService fileMagicService;
  final FfmpegService ffmpegService;
  final DefaultCacheManager cacheManager;
  final CacheManager videoCacheManager;
  final ComputeController? _computeController;

  ComputeController get _compute => _computeController ?? computeController;

  FileDataGateway get _fileDataGateway => fileDataGateway;

  static const String _videoStreamingEnabled = "videoStreamingEnabled";

  bool get isVideoStreamingEnabled {
    if (isLocalGalleryMode) {
      return false;
    }
    return serviceLocator.prefs.getBool(_videoStreamingEnabled) ??
        flagService.streamEnabledByDefault;
  }

  Future<void> setIsVideoStreamingEnabled(bool value) async {
    serviceLocator.prefs.setBool(_videoStreamingEnabled, value).ignore();
    Bus.instance.fire(VideoStreamingChanged());

    if (isVideoStreamingEnabled) {
      queueFiles(duration: Duration.zero);
    } else {
      stop("streaming disabled");
    }
  }

  void _clearQueue() {
    for (final entry in _items.entries) {
      _fireVideoPreviewStateChange(
        entry.key,
        entry.value.status == PreviewItemStatus.uploaded
            ? PreviewItemStatus.uploaded
            : PreviewItemStatus.paused,
      );
    }
    fileQueue.clear();
    _items.clear();
  }

  void stop(String reason) {
    _logger.info("Stopping streaming: $reason");
    _streamingCancelToken?.cancel();
    uploadingFileId = -1;
    _clearQueue();
    _compute.releaseCompute(stream: true);

    if (_currentFfmpegJob != null) {
      unawaited(_currentFfmpegJob!.cancel());
    }
  }

  Future<void> pauseForExport() async {
    _compute.blockCompute(blocker: "video-export");
    final job = _currentFfmpegJob;
    if (job != null) stop("video export");
    await job?.cancel();
  }

  void resumeAfterExport() {
    _compute.unblockCompute(blocker: "video-export");
    queueFiles();
  }

  Future<void> stopSafely(String reason) async {
    final item = uploadingFileId >= 0 ? _items[uploadingFileId] : null;
    if (item == null) return;

    final status = item.status;
    double? progress;

    if (status == PreviewItemStatus.compressing) {
      final durationInSeconds = item.file.duration;
      progress = _currentFfmpegJob?.progress(
        durationInSeconds == null ? null : Duration(seconds: durationInSeconds),
      );
    }

    final progressStr = progress != null
        ? "${(progress * 100).toStringAsFixed(1)}%"
        : "N/A";

    if (status == PreviewItemStatus.uploading ||
        (status == PreviewItemStatus.compressing &&
            progress != null &&
            progress >= 0.75)) {
      _logger.fine(
        "stopSafely: letting current task finish, clearing queue. status: $status, progress: $progressStr, reason: $reason",
      );
      fileQueue.clear();
      return;
    }

    stop("$reason (status: $status, progress: $progressStr)");
  }

  void _fireVideoPreviewStateChange(int fileId, PreviewItemStatus status) {
    Bus.instance.fire(VideoPreviewStateChangedEvent(fileId, status));
  }

  Future<bool> addToManualQueue(EnteFile file, String queueType) async {
    if (file.uploadedFileID == null) return false;

    final bool alreadyInQueue = await uploadLocksDB.isInStreamQueue(
      file.uploadedFileID!,
    );
    if (alreadyInQueue) {
      if (uploadingFileId < 0) {
        queueFiles(duration: Duration.zero, isManual: true, forceProcess: true);
      }
      return false;
    }

    await uploadLocksDB.addToStreamQueue(file.uploadedFileID!, queueType);

    if (uploadingFileId < 0) {
      queueFiles(duration: Duration.zero, isManual: true);
    } else {
      _items[file.uploadedFileID!] = PreviewItem(
        status: PreviewItemStatus.inQueue,
        file: file,
        retryCount: 0,
        collectionID: file.collectionID ?? 0,
      );
      _fireVideoPreviewStateChange(
        file.uploadedFileID!,
        PreviewItemStatus.inQueue,
      );
      fileQueue[file.uploadedFileID!] = file;
    }

    return true;
  }

  bool isCurrentlyProcessing(int? uploadedFileID) {
    if (uploadedFileID == null) return false;

    final item = _items[uploadedFileID];
    if (item != null) {
      switch (item.status) {
        case PreviewItemStatus.inQueue:
        case PreviewItemStatus.compressing:
        case PreviewItemStatus.uploading:
          return true;
        default:
          return false;
      }
    }

    return false;
  }

  PreviewItemStatus? getProcessingStatus(int uploadedFileID) {
    return _items[uploadedFileID]?.status;
  }

  Future<bool> _isRecreateOperation(EnteFile file) async {
    if (file.uploadedFileID == null) return false;

    try {
      // The in-memory manual queue may not be initialized yet.
      final manualQueueFiles = await uploadLocksDB.getStreamQueue();
      final queueType = manualQueueFiles[file.uploadedFileID!];
      return queueType == 'recreate';
    } catch (_) {
      return false;
    }
  }

  Future<void> _ensurePreviewIdsInitialized() async {
    if (fileDataService.previewIds.isEmpty) {
      await fileDataService.syncFDStatus();
    }
  }

  Future<bool> isSharedFileStreamble(EnteFile file) async {
    try {
      await _ensurePreviewIdsInitialized();
      if (fileDataService.previewIds.containsKey(file.uploadedFileID)) {
        return true;
      }
      await _getPreviewUrl(file);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<List<EnteFile>> _getFiles({
    DateTime? beginDate,
    bool onlyFilesWithLocalId = true,
  }) async {
    final userID = config.getUserID();
    if (userID == null) {
      _logger.warning(
        "Skipping video preview queue because user ID is missing. "
        "This can happen if queued preview work runs after logout or account mode changes.",
      );
      return [];
    }
    return await filesDB.getStreamingEligibleVideoFiles(
      beginDate: beginDate,
      userID: userID,
      onlyFilesWithLocalId: onlyFilesWithLocalId,
    );
  }

  Future<double> calcStatus(
    List<EnteFile> files,
    Map<int, PreviewInfo> previewIds,
  ) async {
    final Set<int> processed = previewIds.keys.toSet();
    final Set<int> total = {...processed};

    for (final file in files) {
      if (file.pubMagicMetadata?.sv == 1) {
        continue;
      }
      total.add(file.uploadedFileID!);
    }

    final double netProcessedItems = total.isEmpty
        ? 1
        : (processed.length / total.length).clamp(0, 1);

    final status = netProcessedItems;
    return status;
  }

  Future<double> getStatus() async {
    try {
      await _ensurePreviewIdsInitialized();

      final files = await _getFiles(
        beginDate: null,
        onlyFilesWithLocalId: false,
      );

      return await calcStatus(files, fileDataService.previewIds);
    } catch (e, s) {
      _logger.severe('Error getting Streaming status', e, s);
      rethrow;
    }
  }

  Future<void> chunkAndUploadVideo(
    BuildContext? ctx,
    EnteFile enteFile, {
    bool continuation = false,
    bool forceUpload = false,
  }) async {
    if (_items.isEmpty) return;
    final cancelToken = _streamingCancelToken ??= CancelToken();
    if (cancelToken.isCancelled) return;

    if (FileUploader.instance.isUploading) {
      stop("upload in progress");
      return;
    }

    if (!_isPermissionGranted()) {
      stop("disabled streaming or no compute permission");
      return;
    }

    Object? error;
    bool removeFile = false;
    String? previewDirectory;
    try {
      if (!enteFile.isUploaded) {
        removeFile = true;
        return;
      }
      try {
        final isRecreateOperation = await _isRecreateOperation(enteFile);
        if (!isRecreateOperation && await getPlaylist(enteFile) != null) {
          if (ctx != null && ctx.mounted) {
            showShortToast(ctx, ctx.strings.videoPreviewAlreadyExists);
          }
          removeFile = true;
          return;
        }
      } catch (e, s) {
        if (e is DioException && e.response?.statusCode == 404) {
          _logger.fine(
            "No preview found for ${enteFile.displayName}, will create one",
          );
        } else {
          _logger.warning("Failed to get playlist for $enteFile", e, s);
          error = e;
          return;
        }
      }
      if (cancelToken.isCancelled) return;
      _logger.info(
        "Starting video preview generation for ${enteFile.displayName}",
      );
      final isManual = await uploadLocksDB.isInStreamQueue(
        enteFile.uploadedFileID!,
      );
      if (cancelToken.isCancelled) return;
      var (props, result, file) = await _checkFileForPreviewCreation(
        enteFile,
        isManual,
      );
      if (cancelToken.isCancelled) return;
      if (result) {
        removeFile = true;
        return;
      }

      if (!continuation && uploadingFileId >= 0) {
        if (uploadingFileId == enteFile.uploadedFileID) return;

        _items[enteFile.uploadedFileID!] = PreviewItem(
          status: PreviewItemStatus.inQueue,
          file: enteFile,
          retryCount: forceUpload
              ? 0
              : _items[enteFile.uploadedFileID!]?.retryCount ?? 0,
          collectionID: enteFile.collectionID ?? 0,
        );
        _fireVideoPreviewStateChange(
          enteFile.uploadedFileID!,
          PreviewItemStatus.inQueue,
        );
        fileQueue[enteFile.uploadedFileID!] = enteFile;
        return;
      }

      uploadingFileId = enteFile.uploadedFileID!;
      _items[enteFile.uploadedFileID!] = PreviewItem(
        status: PreviewItemStatus.compressing,
        file: enteFile,
        retryCount: forceUpload
            ? 0
            : _items[enteFile.uploadedFileID!]?.retryCount ?? 0,
        collectionID: enteFile.collectionID ?? 0,
      );
      _fireVideoPreviewStateChange(
        enteFile.uploadedFileID!,
        PreviewItemStatus.compressing,
      );

      file ??= await getFile(enteFile, isOrigin: true);
      if (cancelToken.isCancelled || _items.isEmpty) return;
      if (file == null) {
        error = "Unable to fetch file";
        return;
      }

      props ??= await getVideoProps(file);
      if (cancelToken.isCancelled ||
          _items.isEmpty ||
          !_isPermissionGranted()) {
        return;
      }
      final fileSize = enteFile.fileSize ?? file.lengthSync();

      if (props == null) {
        error =
            "Failed to read FFprobe metadata for ${enteFile.displayName} "
            "(fileID=${enteFile.uploadedFileID})";
        _logger.warning(error);
        return;
      }

      final videoData = List.from(
        props.propData?["streams"] ?? [],
      ).firstWhereOrNull((e) => e["type"] == "video");
      if (videoData == null) {
        error =
            "$_missingVideoStreamError for ${enteFile.displayName} "
            "(fileID=${enteFile.uploadedFileID})";
        _logger.warning("$error; skipping preview creation");
        return;
      }

      final codec = videoData["codec_name"]?.toString().toLowerCase();
      final isH264 = codec?.contains("h264") ?? false;

      final bitrate = props.duration?.inSeconds != null
          ? (fileSize * 8) / props.duration!.inSeconds
          : null;

      final colorTransfer = videoData["color_transfer"]
          ?.toString()
          .toLowerCase();
      final isHDR =
          colorTransfer != null &&
          (colorTransfer == "smpte2084" || colorTransfer == "arib-std-b67");

      final String tempDir = config.getTempDirectory();
      final String prefix =
          "${tempDir}_${enteFile.uploadedFileID}_${newID("pv")}";
      previewDirectory = prefix;
      Directory(prefix).createSync();
      _logger.info('Compressing video ${enteFile.displayName}');
      final key = enc.Key.fromLength(16);

      final keyfile = File('$prefix/keyfile.key');
      keyfile.writeAsBytesSync(key.bytes);

      final keyinfo = File('$prefix/mykey.keyinfo');
      keyinfo.writeAsStringSync(
        "data:text/plain;base64,${key.base64}\n"
        "${keyfile.path}\n",
      );

      _logger.info(
        'Generating HLS Playlist ${enteFile.displayName} at $prefix/output.m3u8',
      );

      final reencodeVideo =
          !(isH264 && bitrate != null && bitrate <= 4000 * 1000);
      final rescaleVideo = !(bitrate != null && bitrate <= 2000 * 1000);
      final needsTonemap = isHDR;
      final applyFPS = (double.tryParse(props.fps ?? "") ?? 100) > 30;

      final videoFilters = <String>[];

      if (reencodeVideo) {
        if (rescaleVideo || needsTonemap) {
          videoFilters.add(
            "scale='if(lt(iw,ih),min(720,iw),-2)':'if(lt(iw,ih),-2,min(720,ih))'",
          );

          if (applyFPS) videoFilters.add("fps=30");
        }

        if (needsTonemap) {
          videoFilters.addAll([
            'zscale=transfer=linear',
            'tonemap=tonemap=hable:desat=0',
            'zscale=primaries=709:transfer=709:matrix=709',
          ]);
        }

        videoFilters.add("format=yuv420p");
      }

      final command = <String>[
        '-i',
        file.path,
        if (videoFilters.isNotEmpty) ...['-vf', videoFilters.join(',')],
        if (reencodeVideo) ...[
          '-c:v',
          'libx264',
          '-maxrate',
          '2000k',
          '-bufsize',
          '4000k',
        ] else ...[
          '-c:v',
          'copy',
        ],
        '-c:a',
        'aac',
        '-b:a',
        '128k',
        '-f',
        'hls',
        '-hls_flags',
        'single_file',
        '-hls_list_size',
        '0',
        '-hls_key_info_file',
        keyinfo.path,
        '$prefix/output.m3u8',
      ];

      final playlistGenResult = await _runFfmpeg(command);
      if (cancelToken.isCancelled) return;

      if (_items.isEmpty) {
        Directory(prefix).delete(recursive: true).ignore();
        return;
      }

      final playlistGenReturnCode = playlistGenResult.returnCode;

      String? objectId;
      int? objectSize;

      if (playlistGenResult.isSuccess) {
        try {
          _items[enteFile.uploadedFileID!] = PreviewItem(
            status: PreviewItemStatus.uploading,
            file: enteFile,
            collectionID: enteFile.collectionID ?? 0,
            retryCount: _items[enteFile.uploadedFileID!]?.retryCount ?? 0,
          );
          _fireVideoPreviewStateChange(
            enteFile.uploadedFileID!,
            PreviewItemStatus.uploading,
          );

          _logger.info('Playlist Generated ${enteFile.displayName}');

          final playlistFile = File("$prefix/output.m3u8");
          final previewFile = File("$prefix/output.ts");
          final result = await uploadVideoPreview(
            previewFile,
            fileID: enteFile.uploadedFileID!,
            gateway: _fileDataGateway,
            dio: serviceLocator.enteDio,
            useUploadV2: flagService.previewUploadV2,
            cancelToken: cancelToken,
          );
          if (cancelToken.isCancelled) return;

          objectId = result.$1;
          objectSize = result.$2;

          final playlistFrameResult = await _runFfmpeg([
            '-allowed_extensions',
            'ALL',
            '-i',
            '$prefix/output.m3u8',
            '-frames:v',
            '1',
            '-c',
            'copy',
            '$prefix/frame.ts',
          ]);
          if (cancelToken.isCancelled) return;
          int? width, height;
          try {
            if (playlistFrameResult.isSuccess) {
              FFProbeProps? playlistFrameProps;
              final file2 = File("$prefix/frame.ts");

              playlistFrameProps = await getVideoProps(file2);
              width = playlistFrameProps?.width;
              height = playlistFrameProps?.height;
            }
          } catch (err, sT) {
            _logger.warning("Failed to fetch resolution of stream", err, sT);
          }
          if (cancelToken.isCancelled) return;

          await _reportVideoPreview(
            enteFile,
            playlistFile,
            objectId: objectId,
            objectSize: objectSize,
            width: width,
            height: height,
            cancelToken: cancelToken,
          );
          if (cancelToken.isCancelled) return;

          _logger.info("Video preview uploaded for $enteFile");
        } catch (err, sT) {
          if (cancelToken.isCancelled) return;
          error = "Failed to upload video preview\nError: $err";
          _logger.shout("Something went wrong with preview upload", err, sT);
        }
      } else {
        final output = playlistGenResult.output;
        _logger.warning(
          "FFmpeg command failed with return code $playlistGenReturnCode\n"
          "${output.isEmpty ? 'FFmpeg output unavailable' : output}",
        );
        error =
            "Failed to generate video preview (return code $playlistGenReturnCode)";
      }

      if (error == null) {
        fileDataService.appendPreview(
          enteFile.uploadedFileID!,
          objectId!,
          objectSize!,
        );

        _items[enteFile.uploadedFileID!] = PreviewItem(
          status: PreviewItemStatus.uploaded,
          file: enteFile,
          retryCount: _items[enteFile.uploadedFileID!]?.retryCount ?? 0,
          collectionID: enteFile.collectionID ?? 0,
        );
        _fireVideoPreviewStateChange(
          enteFile.uploadedFileID!,
          PreviewItemStatus.uploaded,
        );
        _removeFromLocks(enteFile).ignore();
        Directory(prefix).delete(recursive: true).ignore();
      }
    } finally {
      if (cancelToken.isCancelled) {
        if (previewDirectory != null) {
          Directory(previewDirectory).delete(recursive: true).ignore();
        }
      } else {
        if (error != null) {
          _retryFile(enteFile, error);
        } else if (removeFile) {
          _removeFile(enteFile);
          _removeFromLocks(enteFile).ignore();
        }
        final bool shouldStopProcessing = _isNetworkError(error);

        if (fileQueue.isNotEmpty && !shouldStopProcessing) {
          if (error != null) {
            _logger.info(
              "[chunk] Error occurred, waiting before processing next item. Queue size: ${fileQueue.length}",
            );
            await Future.delayed(const Duration(seconds: 2));
          }

          if (!cancelToken.isCancelled && fileQueue.isNotEmpty) {
            _logger.info(
              "[chunk] Processing ${_items.length} items for streaming",
            );
            final entry = fileQueue.entries.first;
            final file = entry.value;
            fileQueue.remove(entry.key);
            if (ctx != null && ctx.mounted) {
              await chunkAndUploadVideo(ctx, file, continuation: true);
            } else {
              await chunkAndUploadVideo(null, file, continuation: true);
            }
          }
        } else {
          stop(shouldStopProcessing ? "network error" : "nothing to process");
        }
      }
    }
  }

  Future<ffmpeg.Result> _runFfmpeg(List<String> arguments) async {
    final job = ffmpegService.start(arguments);
    _currentFfmpegJob = job;
    try {
      return await job.completed;
    } catch (error, stackTrace) {
      _logger.warning("FFmpeg command failed", error, stackTrace);
      return ffmpeg.Result(-1, error.toString());
    } finally {
      if (identical(_currentFfmpegJob, job)) _currentFfmpegJob = null;
    }
  }

  Future<void> _removeFromLocks(EnteFile enteFile) async {
    final bool isFailurePresent =
        _failureFiles?.contains(enteFile.uploadedFileID!) ?? false;
    final bool isInManualQueue = await uploadLocksDB.isInStreamQueue(
      enteFile.uploadedFileID!,
    );

    if (isFailurePresent) {
      await uploadLocksDB.deleteStreamUploadErrorEntry(
        enteFile.uploadedFileID!,
      );
      _failureFiles?.remove(enteFile.uploadedFileID!);
    }

    if (isInManualQueue) {
      await uploadLocksDB.removeFromStreamQueue(enteFile.uploadedFileID!);
    }
  }

  void _removeFile(EnteFile enteFile) {
    final fileId = enteFile.uploadedFileID!;
    _items.remove(fileId);
    // There is no removed status; uploaded also clears the item from the UI.
    _fireVideoPreviewStateChange(fileId, PreviewItemStatus.uploaded);
  }

  bool _isNetworkError(Object? error) {
    if (error is DioException) {
      return error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.unknown ||
          (error.error != null &&
              error.error.toString().contains('ERR_NAME_NOT_RESOLVED'));
    }
    return false;
  }

  void _retryFile(EnteFile enteFile, Object error) {
    bool shouldRetry = true;
    if (_isNetworkError(error)) {
      _logger.fine(
        "Network error detected, marking file as failed instead of retrying",
      );
      shouldRetry = false;
    } else if (error is String && error.startsWith(_missingVideoStreamError)) {
      shouldRetry = false;
      uploadLocksDB.removeFromStreamQueue(enteFile.uploadedFileID!).ignore();
    }

    if (!_items.containsKey(enteFile.uploadedFileID!)) return;

    if (shouldRetry &&
        _items[enteFile.uploadedFileID!]!.retryCount < _maxRetryCount) {
      _items[enteFile.uploadedFileID!] = PreviewItem(
        status: PreviewItemStatus.retry,
        file: enteFile,
        retryCount: _items[enteFile.uploadedFileID!]!.retryCount + 1,
        collectionID: enteFile.collectionID ?? 0,
      );
      _fireVideoPreviewStateChange(
        enteFile.uploadedFileID!,
        PreviewItemStatus.retry,
      );
      fileQueue[enteFile.uploadedFileID!] = enteFile;
    } else {
      _items[enteFile.uploadedFileID!] = PreviewItem(
        status: PreviewItemStatus.failed,
        file: enteFile,
        retryCount: _items[enteFile.uploadedFileID!]!.retryCount,
        collectionID: enteFile.collectionID ?? 0,
        error: error,
      );
      _fireVideoPreviewStateChange(
        enteFile.uploadedFileID!,
        PreviewItemStatus.failed,
      );

      final bool isFailurePresent =
          _failureFiles?.contains(enteFile.uploadedFileID!) ?? false;

      if (isFailurePresent) {
        uploadLocksDB.appendStreamEntry(
          enteFile.uploadedFileID!,
          error.toString(),
        );
      } else {
        uploadLocksDB.appendStreamEntry(
          enteFile.uploadedFileID!,
          error.toString(),
        );
        _failureFiles?.add(enteFile.uploadedFileID!);
      }
    }
  }

  Future<void> _reportVideoPreview(
    EnteFile file,
    File playlist, {
    required String objectId,
    required int objectSize,
    required int? width,
    required int? height,
    required CancelToken cancelToken,
  }) async {
    _logger.fine("Pushing playlist for ${file.uploadedFileID}");
    try {
      final encryptionKey = getFileKey(file);
      final playlistContent = playlist.readAsStringSync();
      final result = await gzipAndEncryptJson({
        "playlist": playlistContent,
        'type': 'hls_video',
        'width': width,
        'height': height,
        'size': objectSize,
      }, encryptionKey);
      await _fileDataGateway.putVideoData(
        fileID: file.uploadedFileID!,
        objectID: objectId,
        objectSize: objectSize,
        playlist: result.encData,
        playlistHeader: result.header,
        cancelToken: cancelToken,
      );
    } catch (e, s) {
      _logger.severe("Failed to report video preview", e, s);
      rethrow;
    }
  }

  String _getCacheKey(String objectKey) {
    return "video_playlist_$objectKey";
  }

  String _getDetailsCacheKey(String objectKey) {
    return "video_playlist_details_$objectKey";
  }

  String _getVideoPreviewKey(String objectKey) {
    return "video_preview_$objectKey";
  }

  Future<PlaylistData?> getPlaylist(EnteFile file) async {
    return await _getPlaylist(file);
  }

  Future<void> _downloadVideoPreviewForCache(
    String previewUrl,
    String objectID,
    EnteFile file,
  ) async {
    try {
      await videoCacheManager.downloadFile(
        previewUrl,
        key: _getVideoPreviewKey(objectID),
      );
    } catch (e, s) {
      _logger.warning(
        "Failed to warm video preview cache for fileID "
        "${file.uploadedFileID}",
        e,
        s,
      );
    }
  }

  Future<bool> prefetchExistingPreview(
    EnteFile file, {
    required int maxPreviewSizeBytes,
    bool Function(int bytes)? tryReserveBytes,
  }) async {
    if (file.fileType != FileType.video || file.uploadedFileID == null) {
      return false;
    }
    await _ensurePreviewIdsInitialized();
    Future<bool> isPreviewCached(PreviewInfo previewInfo) async {
      final cachedPreview = await videoCacheManager.getFileFromCache(
        _getVideoPreviewKey(previewInfo.objectId),
      );
      return cachedPreview != null;
    }

    final previewInfo = fileDataService.previewIds[file.uploadedFileID!];
    if (previewInfo != null) {
      if (await isPreviewCached(previewInfo)) {
        return true;
      }
      if (previewInfo.objectSize > maxPreviewSizeBytes) {
        return false;
      }
    }
    if (!file.isOwner || previewInfo == null) {
      return false;
    }
    final playlist = await _getPlaylist(
      file,
      awaitPreviewCache: true,
      maxPreviewSizeBytes: maxPreviewSizeBytes,
      tryReserveBytes: tryReserveBytes,
    );
    if (playlist == null) {
      return false;
    }
    final warmedPreviewInfo = fileDataService.previewIds[file.uploadedFileID!];
    return warmedPreviewInfo != null &&
        await isPreviewCached(warmedPreviewInfo);
  }

  Future<PlaylistData?> _getPlaylist(
    EnteFile file, {
    bool awaitPreviewCache = false,
    int? maxPreviewSizeBytes,
    bool Function(int bytes)? tryReserveBytes,
  }) async {
    _logger.fine("Getting playlist for $file");

    try {
      late final String objectID;
      final PreviewInfo? previewInfo =
          fileDataService.previewIds[file.uploadedFileID!];
      bool shouldAppendPreview = false;
      (String, String)? previewURLResult;
      if (previewInfo == null) {
        shouldAppendPreview = true;
        previewURLResult = await _getPreviewUrl(file);
        _logger.fine("parsed objectID: ${previewURLResult.$2}");
        objectID = previewURLResult.$2;
      } else {
        objectID = previewInfo.objectId;
      }

      final playlistCache = await cacheManager.getFileFromCache(
        _getCacheKey(objectID),
      );
      final detailsCache = await cacheManager.getFileFromCache(
        _getDetailsCacheKey(objectID),
      );
      for (final cachedFile in [playlistCache, detailsCache]) {
        if (cachedFile != null &&
            await cachedFile.file.length() > maxHlsMetadataBytes) {
          throw const FormatException("HLS metadata exceeds the allowed size");
        }
      }
      late final String playlistTemplate;
      late final Map<String, dynamic> metadata;
      if (playlistCache != null) {
        playlistTemplate = await playlistCache.file.readAsString();
        metadata = detailsCache == null
            ? const {}
            : json.decode(await detailsCache.file.readAsString())
                  as Map<String, dynamic>;
      } else {
        final playlistData = await _getPlaylistData(file);
        if (playlistData == null) return null;
        playlistTemplate = playlistData["playlist"] as String;
        metadata = playlistData;
      }
      final width = metadata["width"] as int?;
      final height = metadata["height"] as int?;
      final size = metadata["size"] as int?;
      final videoFile = (await videoCacheManager.getFileFromCache(
        _getVideoPreviewKey(objectID),
      ))?.file;
      final effectiveSize = size ?? previewInfo?.objectSize;
      final maxPreviewCacheSize =
          maxPreviewSizeBytes ?? _maxPreviewSizeLimitForCache;
      late final String segmentUrl;
      if (videoFile == null) {
        previewURLResult = previewURLResult ?? await _getPreviewUrl(file);
        final canCachePreview =
            effectiveSize != null &&
            effectiveSize <= maxPreviewCacheSize &&
            (tryReserveBytes == null || tryReserveBytes(effectiveSize));
        if (canCachePreview) {
          if (awaitPreviewCache) {
            final previewFile = await videoCacheManager.downloadFile(
              previewURLResult.$1,
              key: _getVideoPreviewKey(objectID),
            );
            segmentUrl = previewFile.file.path;
          } else {
            unawaited(
              _downloadVideoPreviewForCache(
                previewURLResult.$1,
                objectID,
                file,
              ),
            );
            segmentUrl = previewURLResult.$1;
          }
        } else {
          segmentUrl = previewURLResult.$1;
        }
      } else {
        segmentUrl = videoFile.path;
      }
      final finalPlaylist = reconstructHlsPlaylist(
        playlistTemplate,
        segmentUrl,
      );
      if (playlistCache == null) {
        unawaited(
          cacheManager.putFile(
            _getCacheKey(objectID),
            Uint8List.fromList(playlistTemplate.codeUnits),
          ),
        );
        unawaited(
          cacheManager.putFile(
            _getDetailsCacheKey(objectID),
            Uint8List.fromList(
              json.encode({
                "width": width,
                "height": height,
                "size": size,
              }).codeUnits,
            ),
          ),
        );
      }
      final tempDir = await getTemporaryDirectory();
      final playlistFile = File("${tempDir.path}/${file.uploadedFileID}.m3u8");
      await playlistFile.writeAsString(finalPlaylist);
      final String log = (
        StringBuffer()
          ..write("[CACHE-STATUS] ")
          ..write("Video: ${videoFile != null ? '✓' : '✗'} | ")
          ..write("Details: ${detailsCache != null ? '✓' : '✗'} | ")
          ..write("Playlist: ${playlistCache != null ? '✓' : '✗'}"),
      ).toString();
      _logger.fine("Mapped playlist to ${playlistFile.path}, $log");
      final data = PlaylistData(
        preview: playlistFile,
        width: width,
        height: height,
        size: effectiveSize,
        durationInSeconds: parseDurationFromHLS(finalPlaylist),
      );
      if (shouldAppendPreview) {
        fileDataService.appendPreview(file.uploadedFileID!, objectID, size!);
      }
      return data;
    } catch (e, s) {
      _logger.warning(
        "Failed to get video playlist for fileID ${file.uploadedFileID}",
        e,
        s,
      );
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> _getPlaylistData(EnteFile file) async {
    final isPublicCollection = collectionsService.isSharedPublicLink(
      file.collectionID!,
    );
    late final ({String encryptedData, String decryptionHeader})? fetchResult;
    if (isPublicCollection) {
      fetchResult = await _fileDataGateway.fetchPublicFileData(
        baseUrl: endpointConfig.endpoint,
        fileID: file.uploadedFileID!,
        type: "vid_preview",
        headers: collectionsService.publicCollectionHeaders(file.collectionID!),
        nonEnteDio: serviceLocator.nonEnteDio,
      );
    } else {
      fetchResult = await _fileDataGateway.fetchSingleFileData(
        fileID: file.uploadedFileID!,
        type: "vid_preview",
      );
    }
    if (fetchResult == null) return null;
    final encryptionKey = isPublicCollection
        ? getPublicFileKey(file)
        : getFileKey(file);
    return decryptAndUnzipJson(
      encryptionKey,
      encryptedData: fetchResult.encryptedData,
      header: fetchResult.decryptionHeader,
      maxOutputBytes: maxHlsMetadataBytes,
    );
  }

  int? parseDurationFromHLS(String playlist) {
    double totalDuration = 0.0;
    for (final line in LineSplitter.split(playlist)) {
      if (line.startsWith("#EXTINF:")) {
        final durationStr = line.substring(8, line.length - 1);
        final duration = double.tryParse(durationStr);
        if (duration != null) {
          totalDuration += duration;
        }
      }
    }
    return totalDuration > 0 ? totalDuration.round() : null;
  }

  Future<(String, String)> _getPreviewUrl(EnteFile file) async {
    try {
      late String url;
      final previewType = file.fileType == FileType.video
          ? "vid_preview"
          : "img_preview";
      if (collectionsService.isSharedPublicLink(file.collectionID!)) {
        url = await _fileDataGateway.getPublicPreview(
          baseUrl: endpointConfig.endpoint,
          fileID: file.uploadedFileID!,
          type: previewType,
          headers: collectionsService.publicCollectionHeaders(
            file.collectionID!,
          ),
          nonEnteDio: serviceLocator.nonEnteDio,
        );
      } else {
        url = await _fileDataGateway.getPreview(
          fileID: file.uploadedFileID!,
          type: previewType,
        );
      }
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;
      if (segments.isEmpty) throw Exception("Invalid URL");
      final String objectID = segments.last;
      return (url, objectID);
    } catch (e) {
      _logger.warning("Failed to get preview url", e);
      rethrow;
    }
  }

  Future<(FFProbeProps?, bool, File?)> _checkFileForPreviewCreation(
    EnteFile enteFile, [
    bool isManual = false,
  ]) async {
    if ((enteFile.pubMagicMetadata?.sv ?? 0) == 1) {
      _logger.info("Skip Preview due to sv=1 for  ${enteFile.displayName}");
      return (null, true, null);
    }
    if (!isManual) {
      if (enteFile.fileSize == null || enteFile.duration == null) {
        _logger.warning(
          "Skip Preview due to misisng size/duration for ${enteFile.displayName}",
        );
        return (null, true, null);
      }
      final int size = enteFile.fileSize!;
      final int duration = enteFile.duration!;
      if (size >= 500 * 1024 * 1024 || duration > 60) {
        _logger.info("Skip Preview due to size: $size or duration: $duration");
        return (null, true, null);
      }
    }
    FFProbeProps? props;
    File? file;
    bool skipFile = false;
    if (enteFile.fileSize == null && isManual) {
      return (props, skipFile, file);
    }

    final size = enteFile.fileSize ?? 0;
    try {
      final isFileUnder10MB = size <= 10 * 1024 * 1024;
      if (isFileUnder10MB) {
        file = await getFile(enteFile, isOrigin: true);
        if (file != null) {
          props = await getVideoProps(file);
          final videoData = List.from(
            props?.propData?["streams"] ?? [],
          ).firstWhereOrNull((e) => e["type"] == "video");
          final codec = videoData?["codec_name"]?.toString().toLowerCase();
          skipFile = codec?.contains("h264") ?? false;

          if (skipFile) {
            _logger.info(
              "[init] Ignoring file ${enteFile.displayName} for preview due to codec",
            );
            await fileMagicService.updatePublicMagicMetadata(
              [enteFile],
              {streamVersionKey: 1},
            );
            return (props, skipFile, file);
          }
        }
      }
    } catch (e, sT) {
      _logger.warning("Failed to check props", e, sT);
    }
    return (props, skipFile, file);
  }

  Future<bool> _putFilesForPreviewCreation(CancelToken cancelToken) async {
    if (!isVideoStreamingEnabled || !await canUseHighBandwidth()) return false;

    Map<int, String> failureFiles = {};
    Map<int, String> manualQueueFiles = {};
    try {
      failureFiles = await uploadLocksDB.getStreamUploadError();
      _failureFiles = {...failureFiles.keys};

      manualQueueFiles = await uploadLocksDB.getStreamQueue();

      for (final failure in _failureFiles!) {
        if (_items.containsKey(failure)) {
          uploadLocksDB.deleteStreamUploadErrorEntry(failure).ignore();
        }
      }

      for (final queueItem in manualQueueFiles.keys) {
        final queueType = manualQueueFiles[queueItem];
        final hasPreview = fileDataService.previewIds[queueItem] != null;
        if (hasPreview && queueType == 'create') {
          await uploadLocksDB.removeFromStreamQueue(queueItem);
        }
      }

      manualQueueFiles = await uploadLocksDB.getStreamQueue();
    } catch (_) {}

    final files = await _getFiles(
      beginDate: DateTime.now().subtract(const Duration(days: 60)),
      onlyFilesWithLocalId: true,
    );
    if (cancelToken.isCancelled) return false;
    final previewIds = fileDataService.previewIds;

    _logger.info(
      "[init] Found ${files.length} files in last 60 days, ${manualQueueFiles.length} manual queue files: ${manualQueueFiles.keys.toList()}",
    );

    for (final queueFileId in manualQueueFiles.keys) {
      final queueType = manualQueueFiles[queueFileId] ?? 'create';
      final hasPreview = previewIds[queueFileId] != null;

      if (queueType == 'create' && hasPreview) {
        _logger.info(
          "[manual-queue] Skipping file $queueFileId (type=$queueType, hasPreview=$hasPreview)",
        );
        continue;
      }

      var queueFile = files.firstWhereOrNull(
        (f) => f.uploadedFileID == queueFileId,
      );

      queueFile ??= await filesDB
          .getAnyUploadedFile(queueFileId)
          .catchError((e) => null);
      if (cancelToken.isCancelled) return false;

      if (queueFile == null) {
        await uploadLocksDB
            .removeFromStreamQueue(queueFileId)
            .catchError((e) {});
        continue;
      }

      _items[queueFile.uploadedFileID!] = PreviewItem(
        status: PreviewItemStatus.inQueue,
        file: queueFile,
        collectionID: queueFile.collectionID ?? 0,
      );
      _fireVideoPreviewStateChange(
        queueFile.uploadedFileID!,
        PreviewItemStatus.inQueue,
      );
      fileQueue[queueFile.uploadedFileID!] = queueFile;
    }

    if (cancelToken.isCancelled) return false;
    final allFiles = files
        .where(
          (file) =>
              previewIds[file.uploadedFileID] == null &&
              !manualQueueFiles.containsKey(file.uploadedFileID),
        )
        .toList();

    var n = allFiles.length, i = 0;
    while (i < n) {
      final enteFile = allFiles[i];
      final isFailure =
          _failureFiles?.contains(enteFile.uploadedFileID!) ?? false;
      if (isFailure) {
        _items[enteFile.uploadedFileID!] = PreviewItem(
          status: PreviewItemStatus.failed,
          file: enteFile,
          collectionID: enteFile.collectionID ?? 0,
          retryCount: _maxRetryCount,
          error: failureFiles[enteFile.uploadedFileID!],
        );
        _fireVideoPreviewStateChange(
          enteFile.uploadedFileID!,
          PreviewItemStatus.failed,
        );
      }
      if (isFailure) {
        _logger.info(
          "[init] Ignoring file ${enteFile.displayName} for preview",
        );
        allFiles.removeAt(i);
        n--;
        continue;
      }

      _items[enteFile.uploadedFileID!] = PreviewItem(
        status: PreviewItemStatus.inQueue,
        file: enteFile,
        collectionID: enteFile.collectionID ?? 0,
      );
      _fireVideoPreviewStateChange(
        enteFile.uploadedFileID!,
        PreviewItemStatus.inQueue,
      );
      fileQueue[enteFile.uploadedFileID!] = enteFile;

      i++;
    }

    final totalFiles = fileQueue.length;
    if (totalFiles == 0) {
      _logger.fine("[init] No preview to cache");
      return false;
    }

    _logger.info(
      "[init] Processing $totalFiles items for streaming (${manualQueueFiles.length} manual requested, ${fileQueue.length} queued, ${allFiles.length} regular)",
    );

    final entry = fileQueue.entries.first;
    final file = entry.value;
    fileQueue.remove(entry.key);
    chunkAndUploadVideo(null, file).ignore();
    return true;
  }

  bool _allowStream() {
    return isVideoStreamingEnabled && _compute.requestCompute(stream: true);
  }

  bool _allowManualStream() {
    return isVideoStreamingEnabled &&
        _compute.requestCompute(
          stream: true,
          bypassInteractionCheck: true,
          bypassMLWaiting: true,
        );
  }

  bool _isPermissionGranted() {
    return isVideoStreamingEnabled &&
        !_compute.computeBlocked &&
        _compute.computeState == ComputeRunState.generatingStream &&
        _compute.isDeviceHealthy;
  }

  void queueFiles({
    Duration duration = const Duration(seconds: 5),
    bool isManual = false,
    bool forceProcess = false,
  }) {
    Future.delayed(duration, () async {
      if (_hasQueuedFile && !forceProcess) return;

      if (FileUploader.instance.isUploading) {
        _logger.info("Skipping stream queue - file upload in progress");
        return;
      }

      final isStreamAllowed = isManual ? _allowManualStream() : _allowStream();
      if (!isStreamAllowed) return;

      final cancelToken = CancelToken();
      _streamingCancelToken = cancelToken;
      await _ensurePreviewIdsInitialized();
      if (cancelToken.isCancelled) return;
      final result = await _putFilesForPreviewCreation(cancelToken);
      if (!result && !cancelToken.isCancelled) {
        _compute.releaseCompute(stream: true);
      }
    });
  }
}
