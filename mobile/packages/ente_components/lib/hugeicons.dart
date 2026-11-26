import 'package:flutter/widgets.dart';
import 'package:hugeicons/hugeicons.dart' as hugeicons;

export 'package:hugeicons/hugeicons.dart' hide HugeIcon;

class HugeIcon extends StatelessWidget {
  const HugeIcon({
    super.key,
    required this.icon,
    this.color,
    this.secondaryColor,
    this.size = 24.0,
    this.strokeWidth,
  });

  final List<List<dynamic>> icon;
  final Color? color;
  final Color? secondaryColor;
  final double? size;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: hugeicons.HugeIcon(
        icon: icon,
        color: color,
        secondaryColor: secondaryColor,
        size: size,
        strokeWidth: strokeWidth,
      ),
    );
  }
}
