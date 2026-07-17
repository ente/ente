import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import "package:photos/generated/l10n.dart";
import 'package:photos/models/file/file.dart';
import 'package:photos/module/metadata/exif.dart';
import 'package:photos/ui/common/loading_widget.dart';

class ExifInfoDialog extends StatelessWidget {
  final EnteFile file;
  const ExifInfoDialog(this.file, {super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return BottomSheetComponent(
      title: AppLocalizations.of(context).exif,
      isScrollable: true,
      snap: true,
      initialChildSize: 0.75,
      snapSizes: const [0.5, 0.75, 0.95],
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            file.title!,
            style: TextStyles.body.copyWith(color: colors.textLight),
          ),
          const SizedBox(height: Spacing.lg),
          _getInfo(context),
        ],
      ),
    );
  }

  Widget _getInfo(BuildContext context) {
    final colors = context.componentColors;
    return FutureBuilder(
      future: getExif(file),
      builder: (BuildContext context, AsyncSnapshot snapshot) {
        if (snapshot.hasData) {
          final exif = snapshot.data;
          String data = exif.entries
              .map((entry) => "${entry.key}: ${entry.value}")
              .join("\n");
          if (data.isEmpty) {
            data = AppLocalizations.of(context).noExifData;
          }
          return Text(
            data,
            style: TextStyles.body.copyWith(color: colors.textLight),
          );
        } else {
          return const EnteLoadingWidget();
        }
      },
    );
  }
}
