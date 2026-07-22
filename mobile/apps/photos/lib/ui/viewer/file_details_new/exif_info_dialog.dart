import "package:ente_components/ente_components.dart";
import "package:exif_reader/exif_reader.dart";
import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart";

class ExifInfoDialogNew extends StatelessWidget {
  const ExifInfoDialogNew({required this.file, required this.exif, super.key});

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

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.exif,
            style: TextStyles.h2.copyWith(color: colors.textBase),
          ),
          Text(
            file.displayName,
            style: TextStyles.mini.copyWith(color: colors.textLight),
          ),
        ],
      ),
      content: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(Spacing.xs),
            color: colors.fillLight,
            child: Text(
              data,
              style: TextStyles.body.copyWith(
                color: colors.textLight,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.close),
        ),
      ],
    );
  }
}
