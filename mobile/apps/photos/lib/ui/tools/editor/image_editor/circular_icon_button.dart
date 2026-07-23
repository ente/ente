import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import "package:flutter_svg/svg.dart";
import "package:hugeicons/hugeicons.dart";

class CircularIconButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final List<List<dynamic>>? hugeIcon;
  final String? svgPath;
  final IconData? icon;
  final Widget? child;
  final double size;
  final bool isSelected;

  const CircularIconButton({
    super.key,
    required this.label,
    required this.onTap,
    this.hugeIcon,
    this.svgPath,
    this.icon,
    this.child,
    this.size = 60,
    this.isSelected = false,
  }) : assert(
         hugeIcon != null || svgPath != null || icon != null || child != null,
         'One of hugeIcon, svgPath, icon or child must be provided',
       );

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final Widget iconContent;
    if (hugeIcon != null) {
      iconContent = HugeIcon(
        icon: hugeIcon!,
        size: 24,
        color: colors.iconColor,
      );
    } else if (svgPath != null) {
      iconContent = SvgPicture.asset(
        svgPath!,
        width: 12,
        height: 12,
        fit: BoxFit.scaleDown,
        colorFilter: ColorFilter.mode(colors.iconColor, BlendMode.srcIn),
      );
    } else if (icon != null) {
      iconContent = Icon(icon, size: size * 0.4, color: colors.iconColor);
    } else {
      iconContent = child!;
    }

    return SizedBox(
      width: 90,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: onTap,
            child: Container(
              height: size,
              width: size,
              decoration: BoxDecoration(
                color: isSelected
                    ? colors.primary.withValues(alpha: 0.24)
                    : colors.fillLight,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? colors.primary : colors.fillLight,
                  width: 2,
                ),
              ),
              child: Center(child: iconContent),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyles.body.copyWith(color: colors.textBase),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
