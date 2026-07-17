import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:modal_bottom_sheet/modal_bottom_sheet.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/ffmpeg/ffprobe_props.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/file/video_exif_dialog.dart";

class VideoExifRowItem extends StatelessWidget {
  final EnteFile file;
  final FFProbeProps? props;
  const VideoExifRowItem(this.file, this.props, {super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final l10n = AppLocalizations.of(context);
    final props = this.props;
    final String? subtitle;
    final VoidCallback? onTap;
    if (props == null || props.propData == null) {
      subtitle = l10n.loadingExifData;
      onTap = null;
    } else if (props.propData!.isNotEmpty) {
      subtitle = props.bitrate;
      onTap = () => showBarModalBottomSheet(
        context: context,
        builder: (BuildContext context) {
          return VideoExifDialog(props: props);
        },
        shape: const RoundedRectangleBorder(
          side: BorderSide(width: 0),
          borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
        ),
        topControl: const SizedBox.shrink(),
        backgroundColor: getEnteColorScheme(context).backgroundElevated,
        barrierColor: backdropFaintDark,
        enableDrag: true,
      );
    } else {
      subtitle = l10n.noExifData;
      onTap = () => showShortToast(context, l10n.thisImageHasNoExifData);
    }
    return MenuComponent(
      key: const ValueKey("Video info"),
      leading: HugeIcon(
        icon: HugeIcons.strokeRoundedVideo02,
        size: IconSizes.small,
        color: colors.textLight,
      ),
      title: l10n.videoInfo,
      subtitle: subtitle,
      onTap: onTap,
    );
  }
}
