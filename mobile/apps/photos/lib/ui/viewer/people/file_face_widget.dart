import "dart:typed_data";

import 'package:flutter/widgets.dart';
import "package:logging/logging.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/db/offline_files_db.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/models/ml/face/face.dart";
import "package:photos/service_locator.dart" show isLocalGalleryMode;
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/utils/face/face_thumbnail_cache.dart";

final _logger = Logger("FaceWidget");

class FileFaceWidget extends StatefulWidget {
  final EnteFile file;

  // Data to find the right face, in order of preference
  final Uint8List? faceCrop;
  final Face? face;
  final String? clusterID;

  final bool useFullFile;
  final bool thumbnailFallback;

  /// Physical pixel width for image decoding optimization.
  ///
  /// When provided and > 0, the image will be decoded at this width, with height
  /// computed to preserve aspect ratio. This reduces memory usage for small displays.
  ///
  /// Typically calculated as: `(logicalWidth * MediaQuery.devicePixelRatioOf(context)).toInt()`
  ///
  /// If null or <= 0, the image is decoded at full resolution.
  final int? cachedPixelWidth;

  const FileFaceWidget(
    this.file, {
    this.face,
    this.faceCrop,
    this.clusterID,
    this.useFullFile = true,
    this.thumbnailFallback = false,
    this.cachedPixelWidth,
    super.key,
  });

  @override
  State<FileFaceWidget> createState() => _FileFaceWidgetState();
}

class _FileFaceWidgetState extends State<FileFaceWidget> {
  Future<Uint8List?>? faceCropFuture;

  @override
  void initState() {
    super.initState();
    faceCropFuture = _getFaceCrop();
  }

  @override
  void dispose() {
    super.dispose();
    if (widget.faceCrop == null) {
      final fileId = widget.file.uploadedFileID;
      if (fileId != null) {
        checkStopTryingToGenerateFaceThumbnails(
          fileId,
          useFullFile: widget.useFullFile,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: faceCropFuture,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          // Only cacheWidth (not cacheHeight) to preserve aspect ratio.
          // Face crops are typically portrait, so constraining width ensures
          // sufficient height for BoxFit.cover without upscaling.
          final shouldOptimize =
              widget.cachedPixelWidth != null && widget.cachedPixelWidth! > 0;
          final ImageProvider imageProvider = shouldOptimize
              ? Image.memory(
                  snapshot.data!,
                  cacheWidth: widget.cachedPixelWidth,
                ).image
              : MemoryImage(snapshot.data!);
          return Stack(
            fit: StackFit.expand,
            children: [Image(image: imageProvider, fit: BoxFit.cover)],
          );
        } else {
          if (snapshot.hasError) {
            _logger.severe(
              "Error getting cover face",
              snapshot.error,
              snapshot.stackTrace,
            );
          }
          return widget.thumbnailFallback
              ? ThumbnailWidget(widget.file)
              : EnteLoadingWidget(color: getEnteColorScheme(context).fillMuted);
        }
      },
    );
  }

  Future<Uint8List?> _getFaceCrop() async {
    if (widget.faceCrop != null) {
      return widget.faceCrop;
    }
    try {
      final mlDataDB = isLocalGalleryMode
          ? MLDataDB.localGalleryInstance
          : MLDataDB.instance;
      int? recentFileID;
      if (isLocalGalleryMode) {
        final localId = widget.file.localID;
        if (localId == null || localId.isEmpty) {
          _logger.severe("Missing local ID for face crop generation");
          return null;
        }
        recentFileID = await OfflineFilesDB.instance.getOrCreateLocalIntId(
          localId,
        );
      } else {
        recentFileID = widget.file.uploadedFileID;
      }
      if (recentFileID == null) {
        _logger.severe("Missing file ID for face crop generation");
        return null;
      }
      final Face? faceToUse =
          widget.face ??
          await mlDataDB.getCoverFaceForPerson(
            recentFileID: recentFileID,
            clusterID: widget.clusterID,
          );
      if (faceToUse == null) {
        _logger.severe(
          "Cannot find face to crop, widget.face: ${widget.face}, clusterID: ${widget.clusterID}",
        );
      }
      final cropMap = await getCachedFaceCrops(
        widget.file,
        [faceToUse!],
        useFullFile: widget.useFullFile,
        useTempCache: true,
      );
      if (cropMap != null && cropMap[faceToUse.faceID] != null) {
        return cropMap[faceToUse.faceID];
      } else {
        _logger.severe(
          "No face crop found for face ${faceToUse.faceID} in file $recentFileID",
        );
        return null;
      }
    } catch (e, s) {
      _logger.severe(
        "Failed to get face crop for file ${widget.file.uploadedFileID}",
        e,
        s,
      );
      return null;
    }
  }
}
