import "package:ente_components/ente_components.dart";
import "package:exif_reader/exif_reader.dart";
import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart";

class ExifInfoSheetNew extends StatelessWidget {
  const ExifInfoSheetNew({required this.file, required this.exif, super.key});

  final EnteFile file;
  final Map<String, IfdTag> exif;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final l10n = AppLocalizations.of(context);
    final data = exif.isEmpty
        ? l10n.noExifData
        : exif.entries
              .map((entry) => "${entry.key}: ${entry.value}")
              .join("\n");

    return BottomSheetComponent(
      title: l10n.exif,
      closeTooltip: l10n.close,
      isScrollable: true,
      initialChildSize: 0.75,
      snap: true,
      snapSizes: const [0.75],
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            file.displayName,
            style: TextStyles.mini.copyWith(color: colors.textLight),
          ),
          const SizedBox(height: Spacing.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Spacing.md),
            color: colors.fillLight,
            child: Text(
              data,
              style: TextStyles.body.copyWith(
                color: colors.textLight,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
