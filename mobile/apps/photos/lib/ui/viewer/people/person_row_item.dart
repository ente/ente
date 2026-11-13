import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/viewer/people/face_thumbnail_squircle.dart";
import "package:photos/ui/viewer/people/person_face_widget.dart";

class PersonGridItem extends StatelessWidget {
  final PersonEntity person;
  final EnteFile personFile;
  final VoidCallback onTap;
  final double size;

  const PersonGridItem({
    super.key,
    required this.person,
    required this.personFile,
    required this.onTap,
    this.size = 112,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedSize = size <= 0 ? 112.0 : size;
    final textStyle = getEnteTextTheme(context).small;
    final textScaleFactor =
        MediaQuery.textScalerOf(context).scale(textStyle.fontSize!) /
        textStyle.fontSize!;
    final textHeight = 24 * textScaleFactor;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: resolvedSize,
            height: resolvedSize,
            child: FaceThumbnailSquircleClip(
              child: PersonFaceWidget(
                personId: person.remoteID,
                key: ValueKey(person.remoteID),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: textHeight,
            child: Text(
              person.data.name,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: textStyle,
            ),
          ),
        ],
      ),
    );
  }
}
