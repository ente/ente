import "dart:async";
import "dart:collection";
import "dart:convert";
import "dart:io";

import "package:collection/collection.dart";
import "package:dio/dio.dart";
import "package:encrypt/encrypt.dart" as enc;
import "package:ffmpeg_kit_flutter/ffmpeg_kit.dart";
import "package:ffmpeg_kit_flutter/return_code.dart";
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
import "package:photos/generated/intl/app_localizations.dart";
import "package:photos/models/base/id.dart";
import "package:photos/models/ffmpeg/ffprobe_props.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/metadata/file_magic.dart";
import "package:photos/models/preview/playlist_data.dart";
import "package:photos/models/preview/preview_item.dart";
import "package:photos/models/preview/preview_item_status.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/file_magic_service.dart";
import "package:photos/services/filedata/model/file_data.dart";
import "package:photos/services/isolated_ffmpeg_service.dart";
import "package:photos/services/machine_learning/compute_controller.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/utils/exif_util.dart";
import "package:photos/utils/file_key.dart";
import "package:photos/utils/file_uploader.dart";
import "package:photos/utils/file_util.dart";
import "package:photos/utils/gzip.dart";
import "package:photos/utils/network_util.dart";

const _maxRetryCount = 3;
const _maxFfmpegOutputLines = 24;
const _maxFfmpegOutputChars = 4000;
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
      ffmpegService = IsolatedFfmpegService.instance,
      fileMagicService = FileMagicService.instance,
      cacheManager = DefaultCacheManager(),
      videoCacheManager = VideoCacheManager.instance,
      config = Configuration.instance {
    if (flagService.stopStreamProcess) {
      _registerStopSafelyListeners();
    }
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
    this.videoCacheManager,
  );

  static final VideoPreviewService instance =
      VideoPreviewService._privateConstructor();

  int uploadingFileId = -1;
  CancelToken? _streamingCancelToken;
  int? _currentFfmpegSessionId;

  final Configuration config;
  final ServiceLocator serviceLocator;
  final FilesDB filesDB;
  final UploadLocksDB uploadLocksDB;
  final FileMagicService fileMagicService;
  final IsolatedFfmpegService ffmpegService;
  final DefaultCacheManager cacheManager;
  final CacheManager videoCacheManager;

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

  // Clear queue - will be rebuilt from DB when processing resumes
  void clearQueue() {
    // Fire events for all items being cleared so UI can reset
    // Use paused status when flag is enabled (items will resume), otherwise uploaded
    final status = flagService.stopStreamProcess
        ? PreviewItemStatus.paused
        : PreviewItemStatus.uploaded;
    for (final fileId in _items.keys) {
      _fireVideoPreviewStateChange(fileId, status);
    }
    fileQueue.clear();
    _items.clear();
  }

  /// Stop streaming immediately, cancels FFmpeg and network requests.
  void stop(String reason) {
    if (_items.isEmpty) return;

    _logger.info("Stopping streaming: $reason");
    if (flagService.stopStreamProcess) {
      _streamingCancelToken?.cancel();
    }
    uploadingFileId = -1;
    clearQueue();
    computeController.releaseCompute(stream: true);

    if (flagService.stopStreamProcess && _currentFfmpegSessionId != null) {
      unawaited(FFmpegKit.cancel(_currentFfmpegSessionId!));
      _currentFfmpegSessionId = null;
    }
  }

  // Stop streaming process if ffmpeg not started or if ffmpeg progress < 75%
  Future<void> stopSafely(String reason) async {
    if (!flagService.stopStreamProcess) return;

    final item = uploadingFileId >= 0 ? _items[uploadingFileId] : null;
    if (item == null) return;

    final status = item.status;
    double? progress;

    if (status == PreviewItemStatus.compressing) {
      final durationInSeconds = item.file.duration;
      progress = await ffmpegService.getSessionProgress(
        sessionId: _currentFfmpegSessionId,
        duration: durationInSeconds == null
            ? null
            : Duration(seconds: durationInSeconds),
      );
    }

    final progressStr = progress != null
        ? "${(progress * 100).toStringAsFixed(1)}%"
        : "N/A";

    // Don't interrupt upload or compression >= 75%, but clear queue
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

  // Return value indicates file was successfully added to queue or not
  Future<bool> addToManualQueue(EnteFile file, String queueType) async {
    if (file.uploadedFileID == null) return false;

    // Check if already in queue
    final bool alreadyInQueue = await uploadLocksDB.isInStreamQueue(
      file.uploadedFileID!,
    );
    if (alreadyInQueue) {
      // File is already queued, but trigger processing in case it was stalled
      if (uploadingFileId < 0) {
        queueFiles(duration: Duration.zero, isManual: true, forceProcess: true);
      }
      return false; // Indicates file was already in queue
    }

    // Add to persistent database queue
    await uploadLocksDB.addToStreamQueue(file.uploadedFileID!, queueType);

    // Start processing if not already processing
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

    // Also check if file is in queue or other processing states
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
      // Check database directly instead of relying on in-memory _manualQueueFiles
      // which might not be populated yet
      final manualQueueFiles = await uploadLocksDB.getStreamQueue();
      final queueType = manualQueueFiles[file.uploadedFileID!];
      return queueType == 'recreate';
    } catch (_) {
      return false;
    }
  }

  Future<void> _ensurePreviewIdsInitialized() async {
    // Ensure fileDataService previewIds is initialized before using it
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
    // This is the total video files that have streams
    final Set<int> processed = previewIds.keys.toSet();
    // Total: Total Remote video files owned - skipped video files
    //         + processed videos (any platform)
    final Set<int> total = {...processed};

    for (final file in files) {
      // skipped -> don't add
      if (file.pubMagicMetadata?.sv == 1) {
        continue;
      }
      // Include the file to total set
      total.add(file.uploadedFileID!);
    }

    // If total is empty then mark all as processed else compute the ratio
    // of processed files and total remote video files
    // netProcessedItems = processed / total
    final double netProcessedItems = total.isEmpty
        ? 1
        : (processed.length / total.length).clamp(0, 1);

    // Store the data and return it
    final status = netProcessedItems;
    return status;
  }

  Future<double> getStatus() async {
    try {
      await _ensurePreviewIdsInitialized();

      // This will get us all the video files that are present on remote
      // and also that could be / have been skipped due to device
      // limitations
      final files = await _getFiles(
        beginDate: null,
        onlyFilesWithLocalId: false,
      );

      return calcStatus(files, fileDataService.previewIds);
    } catch (e, s) {
      _logger.severe('Error getting Streaming status', e, s);
      rethrow;
    }
  }

  Future<void> chunkAndUploadVideo(
    BuildContext? ctx,
    EnteFile enteFile, {

    /// Indicates this function is an continuation of a chunking thread
    bool continuation = false,
    // not used currently
    bool forceUpload = false,
  }) async {
    if (_items.isEmpty) return;
    _streamingCancelToken ??= CancelToken();

    // Check if file upload is happening before processing video for streaming
    if (flagService.stopStreamProcess && FileUploader.instance.isUploading) {
      stop("upload in progress");
      return;
    }

    if (!_isPermissionGranted()) {
      stop("disabled streaming or no compute permission");
      return;
    }

    Object? error;
    bool removeFile = false;
    try {
      if (!enteFile.isUploaded) {
        removeFile = true;
        return;
      }
      try {
        // check if playlist already exist, but skip this check for 'recreate' operations
        final isRecreateOperation = await _isRecreateOperation(enteFile);
        if (!isRecreateOperation && await getPlaylist(enteFile) != null) {
          if (ctx != null && ctx.mounted) {
            showShortToast(
              ctx,
              AppLocalizations.of(ctx).videoPreviewAlreadyExists,
            );
          }
          removeFile = true;
          return;
        }
      } catch (e, s) {
        if (e is DioException && e.response?.statusCode == 404) {
          // 404 is expected when checking if preview exists
          _logger.fine(
            "No preview found for ${enteFile.displayName}, will create one",
          );
        } else {
          _logger.warning("Failed to get playlist for $enteFile", e, s);
          error = e;
          return;
        }
      }
      _logger.info(
        "Starting video preview generation for ${enteFile.displayName}",
      );
      // elimination case for <=10 MB with H.264
      final isManual = await uploadLocksDB.isInStreamQueue(
        enteFile.uploadedFileID!,
      );
      var (props, result, file) = await _checkFileForPreviewCreation(
        enteFile,
        isManual,
      );
      if (result) {
        removeFile = true;
        return;
      }

      // check if there is already a preview in processing
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

      // everything is fine, let's process
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

      // get file
      file ??= await getFile(enteFile, isOrigin: true);
      if (_items.isEmpty) return;
      if (file == null) {
        error = "Unable to fetch file";
        return;
      }

      // check metadata for bitrate, codec, color space
      props ??= await getVideoPropsAsync(file);
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

      // create temp file & directory for preview generation
      final String tempDir = config.getTempDirectory();
      final String prefix =
          "${tempDir}_${enteFile.uploadedFileID}_${newID("pv")}";
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

      String filters = "";

      if (reencodeVideo) {
        final videoFilters = <String>[];

        if (rescaleVideo || needsTonemap) {
          // scale smaller dimension to 720p (or keep original if less than 720p)
          // portrait: scale width to min(720,iw), landscape: scale height to min(720,ih)
          videoFilters.add(
            "scale='if(lt(iw,ih),min(720,iw),-2)':'if(lt(iw,ih),-2,min(720,ih))'",
          );

          // reduce fps to 30 if it is more than 30
          if (applyFPS) videoFilters.add("fps=30");
        }

        if (needsTonemap) {
          // apply tonemapping for HDR videos
          videoFilters.addAll([
            'zscale=transfer=linear',
            'tonemap=tonemap=hable:desat=0',
            'zscale=primaries=709:transfer=709:matrix=709',
          ]);
        }

        videoFilters.add("format=yuv420p");

        filters = '-vf "${videoFilters.join(",")}" ';
      }

      final command =
          // scaling, fps, tonemapping
          '$filters'
          // video encoding with maxrate cap at 2000kbps to preserve smaller bitrates
          '${reencodeVideo ? '-c:v libx264 -maxrate 2000k -bufsize 4000k ' : '-c:v copy '}'
          // audio encoding
          '-c:a aac -b:a 128k '
          // hls options
          '-f hls -hls_flags single_file '
          '-hls_list_size 0 -hls_key_info_file ${keyinfo.path} ';

      final playlistGenResult = await ffmpegService
          .runFfmpegCancellable(
            '-i "${file.path}" $command$prefix/output.m3u8',
            (id) {
              _currentFfmpegSessionId = id;
              _logger.info("FFmpeg[$id]: $command");
            },
          )
          .whenComplete(() => _currentFfmpegSessionId = null)
          .onError((error, stackTrace) {
            _logger.warning("FFmpeg command failed", error, stackTrace);
            return {};
          });

      if (_items.isEmpty) {
        Directory(prefix).delete(recursive: true).ignore();
        return;
      }

      final playlistGenReturnCode = playlistGenResult["returnCode"] as int?;

      String? objectId;
      int? objectSize;

      if (ReturnCode.success == playlistGenReturnCode) {
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
          final result = await _uploadPreviewVideo(enteFile, previewFile);

          objectId = result.$1;
          objectSize = result.$2;

          // Fetch resolution of generated stream by decrypting a single frame
          final playlistFrameResult = await ffmpegService
              .runFfmpeg(
                '-allowed_extensions ALL -i "$prefix/output.m3u8" -frames:v 1 -c copy "$prefix/frame.ts"',
              )
              .onError((error, stackTrace) {
                _logger.warning(
                  "FFmpeg command failed for frame",
                  error,
                  stackTrace,
                );
                return {};
              });
          final playlistFrameReturnCode =
              playlistFrameResult["returnCode"] as int?;
          int? width, height;
          try {
            if (ReturnCode.success == playlistFrameReturnCode) {
              FFProbeProps? playlistFrameProps;
              final file2 = File("$prefix/frame.ts");

              playlistFrameProps = await getVideoPropsAsync(file2);
              width = playlistFrameProps?.width;
              height = playlistFrameProps?.height;
            }
          } catch (err, sT) {
            _logger.warning("Failed to fetch resolution of stream", err, sT);
          }

          await _reportVideoPreview(
            enteFile,
            playlistFile,
            objectId: objectId,
            objectSize: objectSize,
            width: width,
            height: height,
          );

          _logger.info("Video preview uploaded for $enteFile");
        } catch (err, sT) {
          error = "Failed to upload video preview\nError: $err";
          _logger.shout("Something went wrong with preview upload", err, sT);
        }
      } else {
        final output = playlistGenResult["output"] as String?;
        _logger.warning(
          "FFmpeg command failed with return code $playlistGenReturnCode\n"
          "${_summarizeFfmpegOutput(output)}",
        );
        error =
            "Failed to generate video preview (return code $playlistGenReturnCode)";
      }

      if (error == null) {
        // update previewIds
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
      if (error != null) {
        _retryFile(enteFile, error);
      } else if (removeFile) {
        _removeFile(enteFile);
        _removeFromLocks(enteFile).ignore();
      }
      // Check if we should stop processing due to network errors
      final bool shouldStopProcessing = _isNetworkError(error);

      if (fileQueue.isNotEmpty && !shouldStopProcessing) {
        // If there was an error, add a delay before processing next file
        if (error != null) {
          _logger.info(
            "[chunk] Error occurred, waiting before processing next item. Queue size: ${fileQueue.length}",
          );
          // Add a small delay before processing next file after an error
          await Future.delayed(const Duration(seconds: 2));
        }

        // process next file
        _logger.info("[chunk] Processing ${_items.length} items for streaming");
        final entry = fileQueue.entries.first;
        final file = entry.value;
        fileQueue.remove(entry.key);
        if (ctx != null && ctx.mounted) {
          await chunkAndUploadVideo(ctx, file, continuation: true);
        } else {
          await chunkAndUploadVideo(null, file, continuation: true);
        }
      } else {
        // Release compute when queue is empty or network is unavailable
        stop(shouldStopProcessing ? "network error" : "nothing to process");
      }
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
    // Note: Using 'uploaded' status as there's no 'removed' status in PreviewItemStatus
    // This indicates the item has been successfully processed and removed from queue
    _fireVideoPreviewStateChange(fileId, PreviewItemStatus.uploaded);
  }

  bool _isNetworkError(Object? error) {
    if (error is DioException) {
      // Check for any network-related error
      return error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.unknown ||
          (error.error != null &&
              error.error.toString().contains('ERR_NAME_NOT_RESOLVED'));
    }
    return false;
  }

  void _retryFile(EnteFile enteFile, Object error) {
    // Check if it's a network error that should not be retried immediately
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
        cancelToken: _streamingCancelToken,
      );
    } catch (e, s) {
      _logger.severe("Failed to report video preview", e, s);
      rethrow;
    }
  }

  Future<(String, int)> _uploadPreviewVideo(EnteFile file, File preview) async {
    _logger.fine("Pushing preview for $file");
    try {
      final uploadUrlResult = await _fileDataGateway.getPreviewUploadUrl(
        fileID: file.uploadedFileID!,
        type: "vid_preview",
        cancelToken: _streamingCancelToken,
      );
      final objectSize = preview.lengthSync();
      await serviceLocator.enteDio.put(
        uploadUrlResult.url,
        data: preview.openRead(),
        options: Options(headers: {Headers.contentLengthHeader: objectSize}),
        cancelToken: _streamingCancelToken,
      );
      return (uploadUrlResult.objectID, objectSize);
    } catch (e) {
      _logger.warning("failed to upload previewVideo", e);
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
    if (previewInfo == null && file.isOwner) {
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
    int? width, height, size;

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

      final FileInfo? playlistCache = await cacheManager.getFileFromCache(
        _getCacheKey(objectID),
      );
      final detailsCache = await cacheManager.getFileFromCache(
        _getDetailsCacheKey(objectID),
      );
      String finalPlaylist;
      if (playlistCache != null) {
        finalPlaylist = playlistCache.file.readAsStringSync();
        if (detailsCache != null) {
          final details = json.decode(detailsCache.file.readAsStringSync());
          width = details["width"];
          height = details["height"];
          size = details["size"];
        }
      } else {
        final Map<String, dynamic> playlistData = await _getPlaylistData(file);
        finalPlaylist = playlistData["playlist"];
        width = playlistData["width"];
        height = playlistData["height"];
        size = playlistData["size"];
        unawaited(
          cacheManager.putFile(
            _getCacheKey(objectID),
            Uint8List.fromList((playlistData["playlist"] as String).codeUnits),
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
      final videoFile = (await videoCacheManager.getFileFromCache(
        _getVideoPreviewKey(objectID),
      ))?.file;
      final effectiveSize = size ?? previewInfo?.objectSize;
      final maxPreviewCacheSize =
          maxPreviewSizeBytes ?? _maxPreviewSizeLimitForCache;
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
            finalPlaylist = finalPlaylist.replaceAll(
              '\noutput.ts',
              '\n${previewFile.file.path}',
            );
          } else {
            unawaited(
              _downloadVideoPreviewForCache(
                previewURLResult.$1,
                objectID,
                file,
              ),
            );
            finalPlaylist = finalPlaylist.replaceAll(
              '\noutput.ts',
              '\n${previewURLResult.$1}',
            );
          }
        } else {
          finalPlaylist = finalPlaylist.replaceAll(
            '\noutput.ts',
            '\n${previewURLResult.$1}',
          );
        }
      } else {
        finalPlaylist = finalPlaylist.replaceAll(
          '\noutput.ts',
          '\n${videoFile.path}',
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

  Future<Map<String, dynamic>> _getPlaylistData(EnteFile file) async {
    late final ({String encryptedData, String decryptionHeader}) fetchResult;
    if (collectionsService.isSharedPublicLink(file.collectionID!)) {
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
    final encryptionKey =
        collectionsService.isSharedPublicLink(file.collectionID!)
        ? getPublicFileKey(file)
        : getFileKey(file);
    final playlistData = await decryptAndUnzipJson(
      encryptionKey,
      encryptedData: fetchResult.encryptedData,
      header: fetchResult.decryptionHeader,
    );
    return playlistData;
  }

  int? parseDurationFromHLS(String playlist) {
    final lines = playlist.split("\n");
    double totalDuration = 0.0;
    for (final line in lines) {
      if (line.startsWith("#EXTINF:")) {
        // Extract duration value (e.g., "#EXTINF:2.400000," → "2.400000")
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
          props = await getVideoPropsAsync(file);
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

  // generate stream for all files after cutoff date
  // returns false if it fails to launch chuncking function
  Future<bool> _putFilesForPreviewCreation() async {
    if (!isVideoStreamingEnabled || !await canUseHighBandwidth()) return false;

    Map<int, String> failureFiles = {};
    Map<int, String> manualQueueFiles = {};
    try {
      failureFiles = await uploadLocksDB.getStreamUploadError();
      _failureFiles = {...failureFiles.keys};

      manualQueueFiles = await uploadLocksDB.getStreamQueue();

      // handle case when failures are already previewed
      for (final failure in _failureFiles!) {
        if (_items.containsKey(failure)) {
          uploadLocksDB.deleteStreamUploadErrorEntry(failure).ignore();
        }
      }

      // handle case when manual queue items are already previewed (for 'create' type only)
      for (final queueItem in manualQueueFiles.keys) {
        final queueType = manualQueueFiles[queueItem];
        final hasPreview = fileDataService.previewIds[queueItem] != null;
        if (hasPreview && queueType == 'create') {
          // Remove from queue only if it's a 'create' type and preview exists
          await uploadLocksDB.removeFromStreamQueue(queueItem);
        }
      }

      // Refresh manual queue after cleanup
      manualQueueFiles = await uploadLocksDB.getStreamQueue();
    } catch (_) {}

    final files = await _getFiles(
      beginDate: DateTime.now().subtract(const Duration(days: 60)),
      onlyFilesWithLocalId: true,
    );
    final previewIds = fileDataService.previewIds;

    _logger.info(
      "[init] Found ${files.length} files in last 60 days, ${manualQueueFiles.length} manual queue files: ${manualQueueFiles.keys.toList()}",
    );

    // Add manual queue files first (they have priority)
    for (final queueFileId in manualQueueFiles.keys) {
      final queueType = manualQueueFiles[queueFileId] ?? 'create';
      final hasPreview = previewIds[queueFileId] != null;

      // For create, only add if no preview exists
      if (queueType == 'create' && hasPreview) {
        _logger.info(
          "[manual-queue] Skipping file $queueFileId (type=$queueType, hasPreview=$hasPreview)",
        );
        continue;
      }

      // First try to find the file in the 60-day list
      var queueFile = files.firstWhereOrNull(
        (f) => f.uploadedFileID == queueFileId,
      );

      // If not found in 60-day list, fetch it individually
      queueFile ??= await filesDB
          .getAnyUploadedFile(queueFileId)
          .catchError((e) => null);

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

    // Then add regular files that need processing
    final allFiles = files
        .where(
          (file) =>
              previewIds[file.uploadedFileID] == null &&
              !manualQueueFiles.containsKey(file.uploadedFileID),
        )
        .toList();

    // set all video status to in queue
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

    // take first file and put it for stream generation
    final entry = fileQueue.entries.first;
    final file = entry.value;
    fileQueue.remove(entry.key);
    chunkAndUploadVideo(null, file).ignore();
    return true;
  }

  bool _allowStream() {
    return isVideoStreamingEnabled &&
        computeController.requestCompute(stream: true);
  }

  bool _allowManualStream() {
    return isVideoStreamingEnabled &&
        computeController.requestCompute(
          stream: true,
          bypassInteractionCheck: true,
          bypassMLWaiting: true,
        );
  }

  /// To check if it's enabled, device is healthy and running streaming
  bool _isPermissionGranted() {
    return isVideoStreamingEnabled &&
        computeController.computeState == ComputeRunState.generatingStream &&
        computeController.isDeviceHealthy;
  }

  void queueFiles({
    Duration duration = const Duration(seconds: 5),
    bool isManual = false,
    bool forceProcess = false,
  }) {
    Future.delayed(duration, () async {
      _streamingCancelToken = null; // Reset for new session
      if (_hasQueuedFile && !forceProcess) return;

      // Don't start streaming if file uploads are in progress
      if (flagService.stopStreamProcess && FileUploader.instance.isUploading) {
        _logger.info("Skipping stream queue - file upload in progress");
        return;
      }

      final isStreamAllowed = isManual ? _allowManualStream() : _allowStream();
      if (!isStreamAllowed) return;

      await _ensurePreviewIdsInitialized();
      final result = await _putFilesForPreviewCreation();
      // Cannot proceed to stream generation, would have to release compute ASAP
      if (!result) {
        computeController.releaseCompute(stream: true);
      }
    });
  }
}

String _summarizeFfmpegOutput(String? output) {
  final trimmedOutput = output?.trim();
  if (trimmedOutput == null || trimmedOutput.isEmpty) {
    return "FFmpeg output unavailable";
  }

  final lines = const LineSplitter()
      .convert(trimmedOutput)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  final summarizedLines = lines.length > _maxFfmpegOutputLines
      ? lines.sublist(lines.length - _maxFfmpegOutputLines)
      : lines;
  var summary = summarizedLines.join("\n");
  if (summary.length > _maxFfmpegOutputChars) {
    summary = summary.substring(summary.length - _maxFfmpegOutputChars);
  }

  final wasTruncated =
      lines.length > summarizedLines.length ||
      trimmedOutput.length > _maxFfmpegOutputChars;
  return wasTruncated
      ? "FFmpeg output (truncated):\n$summary"
      : "FFmpeg output:\n$summary";
}
