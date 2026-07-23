import "package:flutter/widgets.dart";
import "package:hugeicons/hugeicons.dart";

const double _hugeIconStrokeWidth = 1.5;

class LegacyKitRowIcon extends StatelessWidget {
  final Color color;
  final double size;

  const LegacyKitRowIcon({required this.color, this.size = 18, super.key});

  @override
  Widget build(BuildContext context) {
    return HugeIcon(
      icon: HugeIcons.strokeRoundedFileFavourite,
      color: color,
      size: size,
      strokeWidth: _hugeIconStrokeWidth,
    );
  }
}

class LegacyKitAlertIcon extends StatelessWidget {
  final double size;

  const LegacyKitAlertIcon({this.size = 18, super.key});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      "assets/warning-red.png",
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}
