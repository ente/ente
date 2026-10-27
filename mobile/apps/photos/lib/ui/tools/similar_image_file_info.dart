import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:photos/theme/ente_theme.dart";

class SimilarImageFileInfo extends StatelessWidget {
  final String displayName;
  final int? fileSize;

  const SimilarImageFileInfo({
    required this.displayName,
    required this.fileSize,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    final size = fileSize;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          displayName,
          style: textTheme.small,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          size == null ? "" : formatBytes(size),
          style: textTheme.miniMuted,
          strutStyle: StrutStyle.fromTextStyle(
            textTheme.miniMuted,
            forceStrutHeight: true,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
