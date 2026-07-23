import "package:ente_components/ente_components.dart";
import "package:exif_reader/exif_reader.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/generated/l10n.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/info_item_widget.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/file/exif_info_dialog.dart";

class BasicExifItemWidget extends StatelessWidget {
  final Map<String, dynamic> exifData;
  const BasicExifItemWidget(this.exifData, {super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final subtitleTextStyle = TextStyles.mini.copyWith(color: colors.textLight);
    return InfoItemWidget(
      key: const ValueKey("Basic EXIF"),
      leadingIconWidget: HugeIcon(
        icon: HugeIcons.strokeRoundedCamera01,
        size: IconSizes.small,
        color: colors.textLight,
      ),
      title: exifData["takenOnDevice"] ?? "--",
      subtitleSection: Future.value([
        if (exifData["fNumber"] != null)
          Text('ƒ/${exifData["fNumber"]}', style: subtitleTextStyle),
        if (exifData["exposureTime"] != null)
          Text(exifData["exposureTime"].toString(), style: subtitleTextStyle),
        if (exifData["focalLength"] != null)
          Text('${exifData["focalLength"]}mm', style: subtitleTextStyle),
        if (exifData["ISO"] != null)
          Text('ISO${exifData["ISO"]}', style: subtitleTextStyle),
      ]),
      useMenuStyle: true,
    );
  }
}

class AllExifItemWidget extends StatelessWidget {
  final EnteFile file;
  final Map<String, IfdTag>? exif;
  const AllExifItemWidget(this.file, this.exif, {super.key});

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
        builder: (BuildContext context) {
          return ExifInfoDialog(file);
        },
        barrierColor: backdropFaintDark,
      );
    } else {
      label = l10n.noExifData;
      onTap = () => showShortToast(context, l10n.thisImageHasNoExifData);
    }

    return InfoItemWidget(
      leadingIconWidget: const HugeIcon(icon: HugeIcons.strokeRoundedLicense),
      title: l10n.exif,
      subtitleSection: [
        Text(label, style: getEnteTextTheme(context).miniBoldMuted),
      ],
      onTap: onTap,
      useMenuStyle: true,
    );
  }
}
