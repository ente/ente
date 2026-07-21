import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:modal_bottom_sheet/modal_bottom_sheet.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/ffmpeg/ffprobe_props.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/info_item_widget.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/file/video_exif_dialog.dart";

class VideoExifRowItem extends StatelessWidget {
  final EnteFile file;
  final FFProbeProps? props;
  const VideoExifRowItem(this.file, this.props, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentProps = props;
    late final String label;
    late final VoidCallback? onTap;
    if (currentProps?.propData == null) {
      label = l10n.loadingExifData;
      onTap = null;
    } else if (currentProps!.propData!.isNotEmpty) {
      label = "${currentProps.videoInfo} ..";
      onTap = () => showBarModalBottomSheet(
        context: context,
        builder: (BuildContext context) {
          return VideoExifDialog(props: currentProps);
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
      label = l10n.noExifData;
      onTap = () => showShortToast(context, l10n.thisImageHasNoExifData);
    }

    return InfoItemWidget(
      leadingIconWidget: const HugeIcon(icon: HugeIcons.strokeRoundedLicense),
      title: l10n.videoInfo,
      subtitleSection: [
        Text(label, style: getEnteTextTheme(context).miniBoldMuted),
      ],
      onTap: onTap,
      useMenuStyle: true,
    );
  }
}
