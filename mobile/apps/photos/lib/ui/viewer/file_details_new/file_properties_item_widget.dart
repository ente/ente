import "dart:async";
import "dart:io";

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:path/path.dart" as path;
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/module/download/file.dart";
import "package:photos/ui/viewer/file_details_new/file_details_exif.dart";
import "package:photos/ui/viewer/file_details_new/file_details_info_item.dart";
import "package:photos/ui/viewer/file_details_new/file_details_skeleton.dart";
import "package:photos/utils/image_util.dart";
import "package:photos/utils/magic_util.dart";

class _FileDetailsProperties {
  const _FileDetailsProperties({
    this.width,
    this.height,
    this.fileSize,
    this.duration,
  });

  factory _FileDetailsProperties.fromFile(EnteFile file) =>
      _FileDetailsProperties(
        width: file.hasDimensions ? file.width : null,
        height: file.hasDimensions ? file.height : null,
        fileSize: file.fileSize,
        duration: file.duration == null || file.duration == 0
            ? null
            : secondsToHHMMSS(file.duration!),
      );

  final int? width;
  final int? height;
  final int? fileSize;
  final String? duration;

  bool needsAsyncLoad(EnteFile file, bool isImage) =>
      fileSize == null ||
      (isImage && (width == null || height == null)) ||
      (file.fileType == FileType.video &&
          duration == null &&
          file.localID != null);
}

Future<_FileDetailsProperties> _loadFileDetailsProperties(
  EnteFile file,
  bool isImage,
) async {
  final initial = _FileDetailsProperties.fromFile(file);
  File? localFile;
  if (initial.fileSize == null ||
      (isImage && (initial.width == null || initial.height == null))) {
    try {
      localFile = await getFile(file);
    } catch (_) {}
  }

  int? width = initial.width;
  int? height = initial.height;
  if (isImage && (width == null || height == null) && localFile != null) {
    // No saved public dimensions (local-only / not-yet-backed-up / removed
    // from Ente). Derive from the actual current local file bytes so we show
    // the real rendered size instead of the (often stale) EXIF tag. Uses the
    // non-origin file (asset.file on iOS = the current rendered image).
    try {
      final dimensions = await getImageDimensions(imagePath: localFile.path);
      width = dimensions?.width;
      height = dimensions?.height;
    } catch (_) {}
  }

  int? fileSize = initial.fileSize;
  if (fileSize == null && localFile != null) {
    try {
      fileSize = await localFile.length();
    } catch (_) {}
  }

  String? duration = initial.duration;
  if (file.fileType == FileType.video &&
      duration == null &&
      file.localID != null) {
    try {
      final asset = await file.getAsset;
      duration = asset?.videoDuration.toString().split(".")[0];
    } catch (_) {}
  }
  return _FileDetailsProperties(
    width: width,
    height: height,
    fileSize: fileSize,
    duration: duration,
  );
}

class FilePropertiesItemWidgetNew extends StatefulWidget {
  const FilePropertiesItemWidgetNew({
    required this.file,
    required this.isImage,
    required this.currentUserID,
    required this.loadDelay,
    required this.exifDetails,
    super.key,
  });

  final EnteFile file;
  final bool isImage;
  final int currentUserID;
  final Duration loadDelay;
  final ValueListenable<FileDetailsExif?> exifDetails;

  @override
  State<FilePropertiesItemWidgetNew> createState() =>
      _FilePropertiesItemWidgetNewState();
}

class _FilePropertiesItemWidgetNewState
    extends State<FilePropertiesItemWidgetNew> {
  late _FileDetailsProperties _properties;
  late bool _isLoadingProperties;
  Timer? _loadTimer;

  @override
  void initState() {
    super.initState();
    _properties = _FileDetailsProperties.fromFile(widget.file);
    _isLoadingProperties = _properties.needsAsyncLoad(
      widget.file,
      widget.isImage,
    );
    if (_isLoadingProperties) {
      _loadTimer = Timer(
        widget.loadDelay,
        () => unawaited(_loadMissingProperties()),
      );
    }
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadMissingProperties() async {
    final properties = await _loadFileDetailsProperties(
      widget.file,
      widget.isImage,
    );
    if (mounted) {
      setState(() {
        _properties = properties;
        _isLoadingProperties = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final subtitles = _subtitles(context);
    return FileDetailsInfoItemNew(
      leading: HugeIcon(
        icon: widget.isImage
            ? HugeIcons.strokeRoundedImage01
            : HugeIcons.strokeRoundedVideo02,
        size: IconSizes.small,
        color: colors.textLight,
      ),
      title:
          path.basenameWithoutExtension(widget.file.displayName) +
          path.extension(widget.file.displayName).toUpperCase(),
      subtitles: subtitles.isNotEmpty
          ? subtitles
          : const [FileDetailsInlineSkeleton()],
      onEdit:
          widget.file.uploadedFileID == null ||
              widget.file.ownerID != widget.currentUserID ||
              widget.file.isTrash
          ? null
          : () async {
              await editFilename(context, widget.file);
              if (mounted) setState(() {});
            },
    );
  }

  List<Widget> _subtitles(BuildContext context) {
    final style = TextStyles.mini.copyWith(
      color: context.componentColors.textLight,
    );
    final result = <Widget>[];
    final exif = widget.exifDetails.value;
    final width = _properties.width;
    final height = _properties.height;
    if (width != null && height != null && width != 0 && height != 0) {
      final megaPixels = (width * height) / 1000000;
      final roundedMegaPixels = (megaPixels * 10).round() / 10.0;
      result.add(
        Text(
          "${roundedMegaPixels.toStringAsFixed(1)}MP   $width x $height",
          style: style,
        ),
      );
    } else if (!_isLoadingProperties &&
        exif?.resolution != null &&
        exif?.megaPixels != null) {
      result.add(
        Text("${exif!.megaPixels}MP   ${exif.resolution}", style: style),
      );
    }
    if (_properties.fileSize != null) {
      result.add(Text(formatBytes(_properties.fileSize!), style: style));
    }
    if (_properties.duration != null) {
      result.add(Text(_properties.duration!, style: style));
    }
    return result;
  }
}
