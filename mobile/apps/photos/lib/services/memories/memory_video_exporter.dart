import "dart:io";
import "dart:math";
import "dart:typed_data";
import "dart:ui";

import "package:logging/logging.dart";
import "package:native_video_editor/native_video_editor.dart";
import "package:photos/core/configuration.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/memories/memory_music_track.dart";
import "package:photos/module/download/file.dart";
import "package:photos/module/download/thumbnail.dart";
import "package:photos/services/memories/memory_music_service.dart";
import "package:photos/services/remote_assets_service.dart";
import "package:photos/utils/image_util.dart";
import "package:uuid/uuid.dart";

typedef SlideshowExport =
    Future<String> Function(
      SlideshowExportRequest request, {
      void Function(double progress)? onProgress,
    });

class MemoryVideoExportException implements Exception {
  final String message;

  const MemoryVideoExportException(this.message);

  @override
  String toString() => "MemoryVideoExportException: $message";
}

class MemoryVideoExporter {
  static const frameWidth = 1080;
  static const frameHeight = 1920;
  static const frameRate = 30;
  static const photoDuration = Duration(seconds: 5);
  static const crossfade = Duration(milliseconds: 600);
  static const musicFadeIn = Duration(milliseconds: 900);
  static const musicFadeOut = Duration(milliseconds: 250);
  static const _nearScale = 1.15;
  static const _farScale = 1.05;
  static const _maxPanFraction = 0.0125;
  static const _downloadProgressShare = 0.2;
  static const _resolveConcurrency = 3;

  static final _logger = Logger("MemoryVideoExporter");

  final Future<File?> Function(EnteFile file) _resolveFile;
  final Future<Uint8List?> Function(EnteFile file) _resolveThumbnail;
  final Future<File> Function(MemoryMusicTrack track) _resolveMusic;
  final SlideshowExport _export;
  final String Function() _outputDirectory;
  final Random _random;

  MemoryVideoExporter({
    Future<File?> Function(EnteFile file)? resolveFile,
    Future<Uint8List?> Function(EnteFile file)? resolveThumbnail,
    Future<File> Function(MemoryMusicTrack track)? resolveMusic,
    SlideshowExport? export,
    String Function()? outputDirectory,
    Random? random,
  }) : _resolveFile = resolveFile ?? getFile,
       _resolveThumbnail = resolveThumbnail ?? getThumbnail,
       _resolveMusic = resolveMusic ?? _cachedMusicFile,
       _export = export ?? NativeVideoEditor.exportSlideshow,
       _outputDirectory =
           outputDirectory ?? Configuration.instance.getTempDirectory,
       _random = random ?? Random();

  static Future<File> _cachedMusicFile(MemoryMusicTrack track) {
    return RemoteAssetsService.instance.getAsset(
      track.url,
      cacheFileName: memoryMusicCacheFileName(track.url),
    );
  }

  Future<File> export({
    required List<EnteFile> files,
    required MemoryMusicTrack? musicTrack,
    required bool muteVideos,
    void Function(double progress)? onProgress,
  }) async {
    if (files.isEmpty) {
      throw const MemoryVideoExportException("No memory items to export");
    }
    final scratchFiles = <File>[];
    try {
      return await _render(
        files: files,
        musicTrack: musicTrack,
        muteVideos: muteVideos,
        scratchFiles: scratchFiles,
        onProgress: onProgress,
      );
    } finally {
      for (final file in scratchFiles) {
        await file.delete().catchError((_) => file);
      }
    }
  }

  Future<File> _render({
    required List<EnteFile> files,
    required MemoryMusicTrack? musicTrack,
    required bool muteVideos,
    required List<File> scratchFiles,
    void Function(double progress)? onProgress,
  }) async {
    final resolvedFiles = List<File?>.filled(files.length, null);
    for (var start = 0; start < files.length; start += _resolveConcurrency) {
      final end = min(start + _resolveConcurrency, files.length);
      await Future.wait([
        for (var index = start; index < end; index++)
          _resolveItem(
            files[index],
            scratchFiles,
          ).then((file) => resolvedFiles[index] = file),
      ]);
      onProgress?.call(_downloadProgressShare * end / files.length);
    }
    final items = <SlideshowItem>[];
    for (var index = 0; index < files.length; index++) {
      final file = files[index];
      final resolved = resolvedFiles[index];
      if (resolved == null) {
        throw MemoryVideoExportException("Could not load ${file.tag}");
      }
      items.add(
        file.fileType == FileType.video
            ? SlideshowItem.video(path: resolved.path, isMuted: muteVideos)
            : SlideshowItem.photo(
                path: resolved.path,
                duration: photoDuration,
                motion: _motionFor(index),
              ),
      );
    }
    SlideshowMusic? music;
    if (musicTrack != null) {
      final musicFile = await _resolveMusic(musicTrack);
      music = SlideshowMusic(
        path: musicFile.path,
        fadeIn: musicFadeIn,
        fadeOut: musicFadeOut,
      );
    }
    final request = SlideshowExportRequest(
      outputPath: "${_outputDirectory()}memory-${const Uuid().v4()}.mp4",
      width: frameWidth,
      height: frameHeight,
      frameRate: frameRate,
      crossfade: crossfade,
      items: items,
      music: music,
    );
    _logger.info(
      "Exporting memory video with ${items.length} items"
      "${music == null ? "" : " and music"}",
    );
    final outputPath = await _export(
      request,
      onProgress: (progress) => onProgress?.call(
        _downloadProgressShare + (1 - _downloadProgressShare) * progress,
      ),
    );
    return File(outputPath);
  }

  Future<File?> _resolveItem(EnteFile file, List<File> scratchFiles) async {
    final extension = file.displayName.split(".").last;
    if (file.fileType == FileType.video || !isRawImageExtension(extension)) {
      return _resolveFile(file);
    }
    final thumbnail = await _resolveThumbnail(file);
    if (thumbnail == null) return null;
    _logger.info("Using the thumbnail of RAW file ${file.tag}");
    final raster = File("${_outputDirectory()}memory-${const Uuid().v4()}.jpg");
    await raster.writeAsBytes(thumbnail, flush: true);
    scratchFiles.add(raster);
    return raster;
  }

  SlideshowMotion _motionFor(int index) {
    final zoomIn = index.isEven;
    return SlideshowMotion(
      startScale: zoomIn ? _farScale : _nearScale,
      endScale: zoomIn ? _nearScale : _farScale,
      startOffset: _randomPan(),
      endOffset: _randomPan(),
    );
  }

  Offset _randomPan() {
    double component() => (_random.nextDouble() - 0.5) * 2 * _maxPanFraction;
    return Offset(component(), component());
  }
}
