import "package:flutter/material.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/theme/effects.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

class MarkerImage extends StatelessWidget {
  final EnteFile file;
  final double seperator;

  const MarkerImage({super.key, required this.file, required this.seperator});

  @override
  Widget build(BuildContext context) {
    final bgColor = getEnteColorScheme(context).backgroundElevated2;
    return Container(
      decoration: BoxDecoration(boxShadow: shadowMenuLight),
      child: Stack(
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: bgColor, width: 2),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(2)),
              child: ThumbnailWidget(file),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: EdgeInsets.only(top: seperator),
              child: CustomPaint(painter: MarkerPointer(bgColor)),
            ),
          ),
        ],
      ),
    );
  }
}

class MarkerPointer extends CustomPainter {
  Color bgColor;
  MarkerPointer(this.bgColor);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = bgColor;

    final path = Path();
    path.moveTo(9, -12);
    path.lineTo(0, -4);
    path.lineTo(-9, -12);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(MarkerPointer oldDelegate) {
    return bgColor != oldDelegate.bgColor;
  }
}
