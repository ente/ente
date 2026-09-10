import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import 'package:path/path.dart' as path;
import "package:photos/models/file/extensions/file_props.dart";
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import "package:photos/module/download/file.dart";
import "package:photos/ui/components/info_item_widget.dart";
import "package:photos/utils/image_util.dart";
import "package:photos/utils/magic_util.dart";

class FilePropertiesItemWidget extends StatefulWidget {
  final EnteFile file;
  final bool isImage;
  final Map<String, dynamic> exifData;
  final int currentUserID;
  const FilePropertiesItemWidget(
    this.file,
    this.isImage,
    this.exifData,
    this.currentUserID, {
    super.key,
  });
  @override
  State<FilePropertiesItemWidget> createState() =>
      _FilePropertiesItemWidgetState();
}

class _FilePropertiesItemWidgetState extends State<FilePropertiesItemWidget> {
  Future<List<Widget>>? _subtitleSectionFuture;
  Object? _cachedExifResolution;
  Object? _cachedExifMegaPixels;
  Color? _cachedTextColor;

  @override
  void initState() {
    super.initState();
    _rememberExifDimensions();
  }

  @override
  void didUpdateWidget(covariant FilePropertiesItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final exifDimensionsChanged =
        _cachedExifResolution != widget.exifData["resolution"] ||
        _cachedExifMegaPixels != widget.exifData["megaPixels"];
    if (oldWidget.file.tag != widget.file.tag || exifDimensionsChanged) {
      _subtitleSectionFuture = null;
    }
    _rememberExifDimensions();
  }

  void _rememberExifDimensions() {
    _cachedExifResolution = widget.exifData["resolution"];
    _cachedExifMegaPixels = widget.exifData["megaPixels"];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final textColor = context.componentColors.textLight;
    if (_cachedTextColor != null && _cachedTextColor != textColor) {
      _subtitleSectionFuture = null;
    }
    _cachedTextColor = textColor;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return InfoItemWidget(
      key: const ValueKey("File properties"),
      leadingIconWidget: HugeIcon(
        icon: widget.isImage
            ? HugeIcons.strokeRoundedImage01
            : HugeIcons.strokeRoundedVideo02,
        size: IconSizes.small,
        color: colors.textLight,
      ),
      title:
          path.basenameWithoutExtension(widget.file.displayName) +
          path.extension(widget.file.displayName).toUpperCase(),
      // Parent EXIF updates rebuild this widget. Keep the already completed
      // properties lookup so the row does not flash a spinner and re-read the
      // same local file on every rebuild.
      subtitleSection: _subtitleSectionFuture ??= _subTitleSection(),
      editOnTap:
          widget.file.uploadedFileID == null ||
              widget.file.ownerID != widget.currentUserID ||
              widget.file.isTrash
          ? null
          : () async {
              await editFilename(context, widget.file);
              setState(() {});
            },
      useMenuStyle: true,
    );
  }

  Future<List<Widget>> _subTitleSection() async {
    final textStyle = TextStyles.mini.copyWith(
      color: context.componentColors.textLight,
    );
    final StringBuffer dimString = StringBuffer();
    int? width;
    int? height;
    if (widget.file.hasDimensions) {
      width = widget.file.width;
      height = widget.file.height;
    } else if (widget.isImage) {
      // EXIF dimensions can be stale after edits. Read the current local file.
      try {
        final localFile = await getFile(widget.file);
        final decoded = localFile != null
            ? await getImageDimensions(imagePath: localFile.path)
            : null;
        if (decoded != null) {
          width = decoded.width;
          height = decoded.height;
        }
      } catch (_) {}
    }
    if (width != null && height != null && width != 0 && height != 0) {
      final double megaPixels = (width * height) / 1000000;
      final double roundedMegaPixels = (megaPixels * 10).round() / 10.0;
      dimString.write('${roundedMegaPixels.toStringAsFixed(1)}MP   ');
      dimString.write('$width x $height');
    } else if (widget.exifData["resolution"] != null &&
        widget.exifData["megaPixels"] != null) {
      dimString.write('${widget.exifData["megaPixels"]}MP   ');
      dimString.write('${widget.exifData["resolution"]}');
    }
    final subSectionWidgets = <Widget>[];

    if (dimString.isNotEmpty) {
      subSectionWidgets.add(Text(dimString.toString(), style: textStyle));
    }

    final fileSize =
        widget.file.fileSize ??
        await getFile(widget.file).then((f) => f?.length());

    if (fileSize != null) {
      subSectionWidgets.add(Text(formatBytes(fileSize), style: textStyle));
    }

    if (widget.file.fileType == FileType.video) {
      final duration = widget.file.duration ?? 0;
      if (duration != 0) {
        subSectionWidgets.add(
          Text(secondsToHHMMSS(duration), style: textStyle),
        );
      } else {
        final asset = await widget.file.getAsset;
        subSectionWidgets.add(
          Text(
            asset?.videoDuration.toString().split(".")[0] ?? "",
            style: textStyle,
          ),
        );
      }
    }

    return Future.value(subSectionWidgets);
  }
}
