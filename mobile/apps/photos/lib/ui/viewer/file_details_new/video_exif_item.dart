import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:modal_bottom_sheet/modal_bottom_sheet.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/ffmpeg/ffprobe_props.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/file/video_exif_dialog.dart";
import "package:photos/ui/viewer/file_details_new/file_details_info_item.dart";

class VideoExifRowItemNew extends StatelessWidget {
  const VideoExifRowItemNew(this.props, {super.key});

  final FFProbeProps? props;

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
        builder: (_) => VideoExifDialog(props: currentProps),
        shape: const RoundedRectangleBorder(
          side: BorderSide(width: 0),
          borderRadius: BorderRadius.vertical(top: Radius.circular(5)),
        ),
        topControl: const SizedBox.shrink(),
        backgroundColor: context.componentColors.fillLight,
        barrierColor: context.componentColors.specialScrim,
        enableDrag: true,
      );
    } else {
      label = l10n.noExifData;
      onTap = () => showShortToast(context, l10n.thisImageHasNoExifData);
    }
    return FileDetailsInfoItemNew(
      leading: const HugeIcon(icon: HugeIcons.strokeRoundedLicense),
      title: l10n.videoInfo,
      subtitles: [
        Text(
          label,
          style: TextStyles.mini.copyWith(
            color: context.componentColors.textLight,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
      onTap: onTap,
    );
  }
}
