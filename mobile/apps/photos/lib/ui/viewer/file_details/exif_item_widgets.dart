import "package:ente_components/ente_components.dart";
import "package:exif_reader/exif_reader.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/generated/l10n.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/file/exif_info_dialog.dart";

class BasicExifItemWidget extends StatelessWidget {
  final Map<String, dynamic> exifData;
  const BasicExifItemWidget(this.exifData, {super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final parts = <String>[];
    if (exifData["fNumber"] != null) {
      parts.add('ƒ/${exifData["fNumber"]}');
    }
    if (exifData["exposureTime"] != null) {
      parts.add(exifData["exposureTime"].toString());
    }
    if (exifData["focalLength"] != null) {
      parts.add('${exifData["focalLength"]}mm');
    }
    if (exifData["ISO"] != null) {
      parts.add('ISO${exifData["ISO"]}');
    }
    return MenuComponent(
      key: const ValueKey("Basic EXIF"),
      leading: HugeIcon(
        icon: HugeIcons.strokeRoundedCamera01,
        size: IconSizes.small,
        color: colors.textLight,
      ),
      title: exifData["takenOnDevice"] ?? "--",
      subtitle: parts.isEmpty ? null : parts.join("   "),
    );
  }
}

class AllExifItemWidget extends StatelessWidget {
  final EnteFile file;
  final Map<String, IfdTag>? exif;
  const AllExifItemWidget(this.file, this.exif, {super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final l10n = AppLocalizations.of(context);
    final String subtitle;
    final VoidCallback? onTap;
    if (exif == null) {
      subtitle = l10n.loadingExifData;
      onTap = null;
    } else if (exif!.isNotEmpty) {
      subtitle = l10n.viewAllExifData;
      onTap = () => showBottomSheetComponent(
        context: context,
        builder: (context) => ExifInfoDialog(file),
      );
    } else {
      subtitle = l10n.noExifData;
      onTap = () => showShortToast(context, l10n.thisImageHasNoExifData);
    }
    return MenuComponent(
      key: const ValueKey("All EXIF"),
      leading: HugeIcon(
        icon: HugeIcons.strokeRoundedCameraLens,
        size: IconSizes.small,
        color: colors.textLight,
      ),
      title: l10n.exif,
      subtitle: subtitle,
      onTap: onTap,
    );
  }
}
