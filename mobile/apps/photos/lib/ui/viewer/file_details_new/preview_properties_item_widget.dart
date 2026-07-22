import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/ffmpeg/ffprobe_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/preview/playlist_data.dart";
import "package:photos/services/video_preview_service.dart";
import "package:photos/ui/viewer/file_details_new/file_details_info_item.dart";
import "package:photos/ui/viewer/file_details_new/file_details_menu_group.dart";
import "package:photos/ui/viewer/file_details_new/file_details_skeleton.dart";

final Logger _logger = Logger("PreviewPropertiesItemWidgetNew");

class PreviewPropertiesItemWidgetNew extends StatefulWidget {
  const PreviewPropertiesItemWidgetNew({
    required this.file,
    required this.loadDelay,
    super.key,
  });

  final EnteFile file;
  final Duration loadDelay;

  @override
  State<PreviewPropertiesItemWidgetNew> createState() =>
      _PreviewPropertiesItemWidgetNewState();
}

class _PreviewPropertiesItemWidgetNewState
    extends State<PreviewPropertiesItemWidgetNew> {
  PlaylistData? _preview;
  Timer? _loadTimer;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadTimer = Timer(widget.loadDelay, () => unawaited(_loadPreview()));
  }

  Future<void> _loadPreview() async {
    PlaylistData? preview;
    try {
      preview = await VideoPreviewService.instance.getPlaylist(widget.file);
    } catch (error, stackTrace) {
      _logger.warning("Unable to load preview properties", error, stackTrace);
    }
    if (!mounted) return;
    setState(() {
      _preview = preview;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _loadTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FileDetailsAnimatedSize(
      child: !_loaded
          ? const FileDetailsSectionSkeleton(
              kind: FileDetailsSkeletonKind.menuRow,
              height: fileDetailsMenuRowHeight,
            )
          : _buildLoaded(context),
    );
  }

  Widget _buildLoaded(BuildContext context) {
    final data = _preview;
    if (data == null) return const SizedBox.shrink();
    final style = TextStyles.mini.copyWith(
      color: context.componentColors.textLight,
    );
    final subtitles = <Widget>[
      if (data.width != null && data.height != null)
        Text("${data.width}x${data.height}", style: style),
      if (data.size != null) Text(formatBytes(data.size!), style: style),
    ];
    if (widget.file.fileType == FileType.video &&
        data.size != null &&
        (widget.file.duration ?? 0) > 0) {
      final bitrate = FFProbeProps.formatBitrate(
        data.size! * 8 / widget.file.duration!,
        "b/s",
      );
      if (bitrate != null) subtitles.add(Text(bitrate, style: style));
    }
    if (subtitles.isEmpty) return const SizedBox.shrink();
    return FileDetailsInfoItemNew(
      leading: HugeIcon(
        icon: HugeIcons.strokeRoundedPlay,
        size: IconSizes.small,
        color: context.componentColors.textLight,
      ),
      title: AppLocalizations.of(context).streamDetails,
      subtitles: subtitles,
    );
  }
}
