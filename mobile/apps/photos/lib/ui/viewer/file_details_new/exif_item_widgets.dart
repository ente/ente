import "package:ente_components/ente_components.dart";
import "package:exif_reader/exif_reader.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/file_details_new/exif_info_dialog.dart";
import "package:photos/ui/viewer/file_details_new/file_details_exif.dart";
import "package:photos/ui/viewer/file_details_new/file_details_info_item.dart";

class BasicExifItemWidgetNew extends StatelessWidget {
  const BasicExifItemWidgetNew(this.exif, {super.key});

  final FileDetailsExif exif;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final style = TextStyles.tiny.copyWith(color: colors.textLight);
    return FileDetailsInfoItemNew(
      leading: HugeIcon(
        icon: HugeIcons.strokeRoundedCamera01,
        size: IconSizes.small,
        color: colors.textLight,
      ),
      title: exif.takenOnDevice ?? "--",
      subtitles: [
        if (exif.fNumber != null) Text("ƒ/${exif.fNumber}", style: style),
        if (exif.exposureTime != null) Text(exif.exposureTime!, style: style),
        if (exif.focalLength != null)
          Text("${exif.focalLength}mm", style: style),
        if (exif.iso != null) Text("ISO${exif.iso}", style: style),
      ],
    );
  }
}

class AllExifItemWidgetNew extends StatelessWidget {
  const AllExifItemWidgetNew(this.file, this.exif, {super.key});

  final EnteFile file;
  final Map<String, IfdTag>? exif;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final currentExif = exif;
    late final String label;
    late final VoidCallback? onTap;
    if (currentExif == null) {
      label = l10n.loadingExifData;
      onTap = null;
    } else if (currentExif.isNotEmpty) {
      label = l10n.viewAllExifData;
      onTap = () => showDialog(
        useRootNavigator: false,
        context: context,
        builder: (_) => ExifInfoDialogNew(file: file, exif: currentExif),
        barrierColor: context.componentColors.specialScrim,
      );
    } else {
      label = l10n.noExifData;
      onTap = () => showShortToast(context, l10n.thisImageHasNoExifData);
    }
    return FileDetailsInfoItemNew(
      leading: const HugeIcon(icon: HugeIcons.strokeRoundedLicense),
      title: l10n.exif,
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
