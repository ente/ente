import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/ffmpeg/ffprobe_props.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/models/file/file_type.dart";
import "package:photos/services/video_preview_service.dart";

class PreviewPropertiesItemWidget extends StatefulWidget {
  final EnteFile file;
  final bool isImage;
  final Map<String, dynamic> exifData;
  final int currentUserID;
  const PreviewPropertiesItemWidget(
    this.file,
    this.isImage,
    this.exifData,
    this.currentUserID, {
    super.key,
  });
  @override
  State<PreviewPropertiesItemWidget> createState() =>
      _PreviewPropertiesItemWidgetState();
}

class _PreviewPropertiesItemWidgetState
    extends State<PreviewPropertiesItemWidget> {
  String? _subtitle;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _getSection());
  }

  @override
  Widget build(BuildContext context) {
    if (_subtitle == null) return const SizedBox();
    final colors = context.componentColors;
    return MenuComponent(
      key: const ValueKey("Stream properties"),
      leading: HugeIcon(
        icon: HugeIcons.strokeRoundedPlay,
        size: IconSizes.small,
        color: colors.textLight,
      ),
      title: AppLocalizations.of(context).streamDetails,
      subtitle: _subtitle,
    );
  }

  Future<void> _getSection() async {
    if (!mounted) return;

    final parts = <String>[];

    final data = await VideoPreviewService.instance
        .getPlaylist(widget.file)
        .onError((error, stackTrace) {
          return null;
        });
    if (data == null) return;

    if (!mounted) return;

    if (data.width != null && data.height != null) {
      parts.add("${data.width!}x${data.height!}");
    }

    if (data.size != null) {
      parts.add(formatBytes(data.size!));
    }

    if ((widget.file.fileType == FileType.video) &&
        (widget.file.localID != null || widget.file.duration != 0) &&
        data.size != null) {
      final result = FFProbeProps.formatBitrate(
        data.size! * 8 / widget.file.duration!,
        "b/s",
      );
      if (result != null) {
        parts.add(result);
      }
    }

    if (parts.isEmpty) return;

    _subtitle = parts.join("   ");
    if (mounted) {
      setState(() {});
    }
  }
}
