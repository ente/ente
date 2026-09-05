import "dart:io";

import "package:flutter/foundation.dart";
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import "package:photos/states/detail_page_state.dart";
import "package:photos/ui/viewer/file/qr_code_detection_helper.dart";
import "package:photos/ui/viewer/file/video_widget.dart";
import "package:photos/ui/viewer/file/zoomable_live_image_new.dart";

class FileWidget extends StatelessWidget {
  final EnteFile file;
  final String tagPrefix;
  final Function(bool)? shouldDisableScroll;
  final FullScreenRequestCallback? playbackCallback;
  final BoxDecoration? backgroundDecoration;
  final bool? autoPlay;
  final bool? isFromMemories;
  final bool isActive;
  final int? itemIndex;
  final ValueListenable<int>? activeItemIndexListenable;
  final bool? isAudioMutedOverride;
  final ValueNotifier<double>? playbackSpeed;
  final Function({required int memoryDuration})? onFinalFileLoad;
  final ValueChanged<File>? onFinalImageLoaded;
  final ValueNotifier<QrCodeDetectionResult?>? qrDetectionsNotifier;
  final GestureLongPressStartCallback? onTextSelectionStart;

  const FileWidget(
    this.file, {
    this.autoPlay,
    this.shouldDisableScroll,
    this.playbackCallback,
    required this.tagPrefix,
    this.backgroundDecoration,
    this.isFromMemories = false,
    this.isActive = true,
    this.itemIndex,
    this.activeItemIndexListenable,
    this.isAudioMutedOverride,
    this.playbackSpeed,
    this.onFinalFileLoad,
    this.onFinalImageLoaded,
    this.qrDetectionsNotifier,
    this.onTextSelectionStart,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // Deleting a file can change the file at this index. Key by file identity.
    final String fileKey = _fileWidgetKey(file);
    if (file.fileType == FileType.livePhoto ||
        file.fileType == FileType.image) {
      return ZoomableLiveImageNew(
        file,
        shouldDisableScroll: shouldDisableScroll,
        tagPrefix: tagPrefix,
        backgroundDecoration: backgroundDecoration,
        isFromMemories: isFromMemories ?? false,
        key: key ?? ValueKey(fileKey),
        onFinalFileLoad: onFinalFileLoad,
        onFinalImageLoaded: onFinalImageLoaded,
        qrDetectionsNotifier: qrDetectionsNotifier,
        onTextSelectionStart: onTextSelectionStart,
        isActive: isActive,
        itemIndex: itemIndex,
        activeItemIndexListenable: activeItemIndexListenable,
      );
    } else if (file.fileType == FileType.video) {
      // use old video widget on iOS simulator as the new one crashes while
      // playing certain videos on iOS simulator
      // if (kDebugMode && Platform.isIOS) {
      //   return VideoWidgetChewie(
      //     file,
      //     tagPrefix: tagPrefix,
      //     playbackCallback: playbackCallback,
      //   );
      // }

      return VideoWidget(
        file,
        tagPrefix: tagPrefix,
        playbackCallback: playbackCallback,
        shouldDisableScroll: shouldDisableScroll,
        onFinalFileLoad: onFinalFileLoad,
        isFromMemories: isFromMemories ?? false,
        isActive: isActive,
        itemIndex: itemIndex,
        activeItemIndexListenable: activeItemIndexListenable,
        isAudioMutedOverride: isAudioMutedOverride,
        playbackSpeed: playbackSpeed,
        key: key ?? ValueKey(fileKey),
      );
    } else {
      Logger('FileWidget').severe('unsupported file type ${file.fileType}');
      return const Icon(Icons.error);
    }
  }
}

String _fileWidgetKey(EnteFile file) {
  final baseKey =
      "file_genID_${file.generatedID}___file_id_${file.uploadedFileID}";
  if (file.generatedID != null || file.uploadedFileID != null) {
    return baseKey;
  }

  final localID = file.localID;
  if (localID == null || localID.isEmpty) {
    return baseKey;
  }
  return "${baseKey}___local_id_$localID";
}
