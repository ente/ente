import "dart:async";
import 'dart:io';
import "dart:math";

import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import 'package:flutter/material.dart';
import "package:logging/logging.dart";
import 'package:native_video_editor/native_video_editor.dart';
import 'package:path/path.dart' as path;
import "package:photo_manager/photo_manager.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/db/files_db.dart";
import "package:photos/events/local_photos_updated_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/location/location.dart";
import "package:photos/module/metadata/local_file.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/sync/sync_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/linear_progress_dialog.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/tools/editor/export_video_service.dart";
import "package:photos/ui/tools/editor/native_video_export_service.dart";
import 'package:photos/ui/tools/editor/video_crop_page.dart';
import "package:photos/ui/tools/editor/video_crop_util.dart";
import "package:photos/ui/tools/editor/video_editor/video_editor_app_bar.dart";
import "package:photos/ui/tools/editor/video_editor/video_editor_bottom_action.dart";
import "package:photos/ui/tools/editor/video_editor/video_editor_controller.dart";
import "package:photos/ui/tools/editor/video_editor/video_editor_main_actions.dart";
import "package:photos/ui/tools/editor/video_editor/video_editor_player_control.dart";
import "package:photos/ui/tools/editor/video_editor/video_editor_widgets.dart";
import "package:photos/ui/tools/editor/video_rotate_page.dart";
import "package:photos/ui/tools/editor/video_trim_page.dart";
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:photos/utils/gallery_save_title.dart";

class VideoEditorPage extends StatefulWidget {
  const VideoEditorPage({
    super.key,
    required this.file,
    required this.ioFile,
    required this.detailPageConfig,
  });

  final EnteFile file;
  final File ioFile;
  final DetailPageConfiguration detailPageConfig;

  @override
  State<VideoEditorPage> createState() => _VideoEditorPageState();
}

class _VideoEditorPageState extends State<VideoEditorPage> {
  final _isExporting = ValueNotifier<bool>(false);
  final _logger = Logger("VideoEditor");

  VideoEditorController? _controller;

  late bool _useNativeExport;

  @override
  void initState() {
    super.initState();

    _useNativeExport = flagService.useNativeVideoEditor;

    _controller = VideoEditorController.file(widget.ioFile);
    unawaited(_initializeController());
  }

  Future<void> _initializeController() async {
    try {
      await _controller!.initialize();
      if (mounted) setState(() {});
    } on VideoMinimumDurationError {
      if (mounted) Navigator.pop(context);
    } catch (error, stackTrace) {
      _logger.severe('Failed to initialize video editor', error, stackTrace);
      if (mounted) {
        showShortToast(context, context.strings.somethingWentWrong);
        Navigator.pop(context);
      }
    }
  }

  @override
  void dispose() {
    _isExporting.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isExporting.value) {
          return;
        }
        replacePage(context, DetailPage(widget.detailPageConfig));
      },
      child: ValueListenableBuilder<bool>(
        valueListenable: _isExporting,
        builder: (context, isExporting, _) {
          final isReady = _controller?.initialized ?? false;

          return Scaffold(
            backgroundColor: colorScheme.backgroundColour,
            appBar: VideoEditorAppBar(
              onCancel: () {
                if (isExporting) return;
                replacePage(context, DetailPage(widget.detailPageConfig));
              },
              primaryActionLabel: context.strings.saveCopy,
              onPrimaryAction: exportVideo,
              isPrimaryEnabled: isReady && !isExporting,
            ),
            body: isReady
                ? SafeArea(
                    top: false,
                    bottom: true,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Positioned.fill(
                                    child: Hero(
                                      tag: "video-editor-preview",
                                      child: VideoEditorPreview(
                                        controller: _controller!,
                                      ),
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 24,
                                      ),
                                      child: VideoEditorPlayerControl(
                                        controller: _controller!,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (flagService.internalUser)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    "Native (i)",
                                    style: getEnteTextTheme(context).mini
                                        .copyWith(color: colorScheme.textMuted),
                                  ),
                                  const SizedBox(width: 4),
                                  Transform.scale(
                                    scale: 0.8,
                                    child: Switch(
                                      value: _useNativeExport,
                                      onChanged: (value) {
                                        setState(() {
                                          _useNativeExport = value;
                                        });
                                      },
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (flagService.internalUser)
                            const SizedBox(height: 8),
                          VideoEditorMainActions(
                            children: [
                              VideoEditorBottomAction(
                                label: context.strings.trim,
                                svgPath:
                                    "assets/video-editor/video-editor-trim-action.svg",
                                onPressed: () => _openSubEditor(
                                  VideoTrimPage(controller: _controller!),
                                ),
                              ),
                              const SizedBox(width: 24),
                              VideoEditorBottomAction(
                                label: context.strings.crop,
                                svgPath:
                                    "assets/video-editor/video-editor-crop-action.svg",
                                onPressed: () => _openSubEditor(
                                  VideoCropPage(controller: _controller!),
                                ),
                              ),
                              const SizedBox(width: 24),
                              VideoEditorBottomAction(
                                label: context.strings.rotate,
                                svgPath:
                                    "assets/video-editor/video-editor-rotate-action.svg",
                                onPressed: () => _openSubEditor(
                                  VideoRotatePage(controller: _controller!),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  )
                : const Center(child: CircularProgressIndicator()),
          );
        },
      ),
    );
  }

  void exportVideo() async {
    final shouldUseNative = flagService.internalUser
        ? _useNativeExport
        : flagService.useNativeVideoEditor;

    _logEditState(shouldUseNative: shouldUseNative);

    _isExporting.value = true;

    final dialogKey = GlobalKey<LinearProgressDialogState>();
    final dialog = LinearProgressDialog(
      context.strings.savingEdits,
      key: dialogKey,
    );

    unawaited(
      showDialog(
        useRootNavigator: false,
        context: context,
        builder: (context) {
          return dialog;
        },
      ),
    );

    try {
      final result = await _performExport(
        shouldUseNative: shouldUseNative,
        dialogKey: dialogKey,
      );
      await _handleExportCompletion(result, dialogKey);
    } catch (e, s) {
      _logger.severe("Unexpected error in export process", e, s);
      _isExporting.value = false;

      if (dialogKey.currentState != null && dialogKey.currentState!.mounted) {
        Navigator.of(dialogKey.currentContext!).pop();
      }

      if (!mounted) return;
      showShortToast(context, context.strings.somethingWentWrong);
    }
  }

  Future<File> _performExport({
    required bool shouldUseNative,
    required GlobalKey<LinearProgressDialogState> dialogKey,
  }) async {
    if (shouldUseNative) {
      try {
        return await _runNativeExportWithRetry(dialogKey: dialogKey);
      } catch (nativeError, stackTrace) {
        if (nativeError is NativeVideoEditorException) {
          _logger.warning(
            "Native export failed, attempting FFmpeg fallback (code=${nativeError.code}, details=${nativeError.details})",
            nativeError,
          );
        } else {
          _logger.warning(
            "Native export failed, attempting FFmpeg fallback",
            nativeError,
          );
        }

        if (flagService.internalUser && mounted) {
          showShortToast(context, "(i) Switching to FFmpeg fallback");
        }

        if (dialogKey.currentState != null) {
          dialogKey.currentState!.setProgress(0.0);
        }

        _logger.fine(
          "Falling back to FFmpeg after native failure",
          nativeError,
          stackTrace,
        );
      }
    }

    return await _runFfmpegExportWithRetry(dialogKey: dialogKey);
  }

  Future<File> _runNativeExportWithRetry({
    required GlobalKey<LinearProgressDialogState> dialogKey,
  }) => _runExportWithRetry(
    label: 'Native',
    outputPrefix: 'ente-native-export',
    dialogKey: dialogKey,
    export: (outputPath) => NativeVideoExportService.exportVideo(
      controller: _controller!,
      outputPath: outputPath,
      onProgress: (progress) => dialogKey.currentState?.setProgress(progress),
      onError: (e, s) {
        if (e is NativeVideoEditorException) {
          _logger.severe(
            "Error exporting video with native (code=${e.code}, details=${e.details})",
            e,
            s,
          );
        } else {
          _logger.severe("Error exporting video with native", e, s);
        }
      },
    ),
  );

  Future<File> _runFfmpegExportWithRetry({
    required GlobalKey<LinearProgressDialogState> dialogKey,
  }) => _runExportWithRetry(
    label: 'FFmpeg',
    outputPrefix: 'ente-ffmpeg-export',
    dialogKey: dialogKey,
    export: (outputPath) => ExportService.exportVideo(
      controller: _controller!,
      outputPath: outputPath,
      onProgress: (progress) => dialogKey.currentState?.setProgress(progress),
      onError: (error, stackTrace) {
        _logger.severe("Error exporting video with FFmpeg", error, stackTrace);
      },
    ),
  );

  Future<File> _runExportWithRetry({
    required String label,
    required String outputPrefix,
    required GlobalKey<LinearProgressDialogState> dialogKey,
    required Future<File> Function(String outputPath) export,
  }) async {
    const retryThreshold = Duration(seconds: 1);
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) dialogKey.currentState?.setProgress(0);
      final outputPath = path.join(
        Directory.systemTemp.path,
        '$outputPrefix-${DateTime.now().microsecondsSinceEpoch}-$attempt.mp4',
      );
      final startTime = DateTime.now();
      try {
        return await export(outputPath);
      } catch (error, stackTrace) {
        await _deleteTemporaryOutput(outputPath);
        final elapsed = DateTime.now().difference(startTime);
        if (attempt == 0 && elapsed <= retryThreshold) {
          _logger.info(
            "$label export failed quickly; retrying with a fresh output path",
            error,
            stackTrace,
          );
          continue;
        }
        if (attempt == 0) {
          _logger.info(
            "$label export failed after ${elapsed.inMilliseconds}ms; skipping retry",
            error,
            stackTrace,
          );
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
    throw StateError('$label export exhausted its retry attempts');
  }

  Future<void> _handleExportCompletion(
    File result,
    GlobalKey<LinearProgressDialogState> dialogKey,
  ) async {
    var notificationsStopped = false;
    try {
      _isExporting.value = false;
      if (!mounted) {
        return;
      }

      final fileName =
          path.basenameWithoutExtension(widget.file.title!) +
          "_edited_" +
          DateTime.now().microsecondsSinceEpoch.toString() +
          ".mp4";
      final galleryTitle = await getMediaStoreCompatibleTitle(fileName);

      // Insert the edited file before asset notifications trigger a sync.
      await PhotoManager.stopChangeNotify();
      notificationsStopped = true;

      try {
        final AssetEntity newAsset = await (PhotoManager.editor.saveVideo(
          result,
          title: galleryTitle,
        ));

        final newFile = fileFromAsset(widget.file.deviceFolder ?? '', newAsset);

        newFile.creationTime = widget.file.creationTime;
        newFile.collectionID = widget.file.collectionID;
        newFile.location = widget.file.location;
        if (!newFile.hasLocation && widget.file.localID != null) {
          final assetEntity = await widget.file.getAsset;
          if (assetEntity != null) {
            final latLong = await assetEntity.latlngAsync();
            if (latLong != null) {
              newFile.location = Location(
                latitude: latLong.latitude,
                longitude: latLong.longitude,
              );
            }
          }
        }

        newFile.generatedID = await FilesDB.instance.insertAndGetId(newFile);

        Bus.instance.fire(
          LocalPhotosUpdatedEvent([newFile], source: "editSave"),
        );

        SyncService.instance.sync().ignore();

        if (!mounted) return;
        showShortToast(context, context.strings.editsSaved);
        final files = List<EnteFile>.of(widget.detailPageConfig.files);

        int selectionIndex = files.indexWhere(
          (file) => file.generatedID == newFile.generatedID,
        );
        if (selectionIndex == -1) {
          final fallbackIndex = min(
            max(widget.detailPageConfig.selectedIndex, 0),
            files.length,
          );
          final originalIndex = widget.file.generatedID == null
              ? -1
              : files.indexWhere(
                  (file) => file.generatedID == widget.file.generatedID,
                );
          selectionIndex = originalIndex == -1 ? fallbackIndex : originalIndex;
          files.insert(selectionIndex, newFile);
        }
        _closeProgressDialog(dialogKey);

        if (!mounted) return;
        replacePage(
          context,
          DetailPage(
            widget.detailPageConfig.copyWith(
              files: files,
              selectedIndex: min(selectionIndex, files.length - 1),
            ),
          ),
        );
      } catch (e, s) {
        _logger.severe("Error in post-processing", e, s);
        _closeProgressDialog(dialogKey);
        if (mounted) {
          showShortToast(context, context.strings.somethingWentWrong);
        }
      }
    } finally {
      await _deleteTemporaryOutput(result.path);
      if (notificationsStopped) {
        await PhotoManager.startChangeNotify();
      }
    }
  }

  Future<void> _deleteTemporaryOutput(String outputPath) async {
    try {
      await deleteFileSystemEntityIfPresent(File(outputPath));
    } on FileSystemException catch (error, stackTrace) {
      _logger.warning(
        'Failed to delete temporary video output: $outputPath',
        error,
        stackTrace,
      );
    }
  }

  void _closeProgressDialog(GlobalKey<LinearProgressDialogState> dialogKey) {
    final dialogContext = dialogKey.currentContext;
    if (dialogContext != null) {
      Navigator.of(dialogContext).pop('dialog');
    }
  }

  Future<void> _openSubEditor(Widget child) {
    return Navigator.of(context).push(_VideoEditorSubPageRoute(child));
  }

  void _logEditState({required bool shouldUseNative}) {
    final controller = _controller;
    if (controller == null) {
      _logger.info(
        "Export requested but controller not ready (native=$shouldUseNative)",
      );
      return;
    }

    final rotation = controller.rotation;
    final startTrimMs = controller.startTrim.inMilliseconds;
    final endTrimMs = controller.endTrim.inMilliseconds;
    final trimmedDurationMs = controller.trimmedDuration.inMilliseconds;
    final videoDurationMs = controller.videoDuration.inMilliseconds;
    String fileSpaceCropSummary;
    try {
      final crop = VideoCropUtil.calculateFileSpaceCrop(controller: controller);
      fileSpaceCropSummary =
          "file(x=${crop.x}, y=${crop.y}, w=${crop.width}, h=${crop.height})";
    } catch (e) {
      fileSpaceCropSummary = "file=unavailable(${e.runtimeType})";
    }

    final cropInfo =
        "normalized(min=${_formatOffset(controller.minCrop)}, max=${_formatOffset(controller.maxCrop)}), "
        "$fileSpaceCropSummary"
        "${controller.preferredCropAspectRatio != null ? ", aspectRatio=${controller.preferredCropAspectRatio!.toStringAsFixed(3)}" : ""}";

    _logger.info(
      "Export starting (native=$shouldUseNative) rotation=$rotation°, "
      "trim={startMs:$startTrimMs, endMs:$endTrimMs, durationMs:$trimmedDurationMs, "
      "minMs:0, maxMs:$videoDurationMs, "
      "videoDurationMs:$videoDurationMs} "
      "crop={$cropInfo}",
    );
  }

  String _formatOffset(Offset offset) =>
      "(${offset.dx.toStringAsFixed(3)}, ${offset.dy.toStringAsFixed(3)})";
}

class _VideoEditorSubPageRoute extends PageRouteBuilder<void> {
  _VideoEditorSubPageRoute(this.child)
    : super(
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, _, _) => child,
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
            child: child,
          );
        },
      );

  final Widget child;
}
