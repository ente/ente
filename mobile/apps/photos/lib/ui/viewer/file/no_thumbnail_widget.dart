import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import "package:flutter_svg/flutter_svg.dart";

class NoThumbnailWidget extends StatelessWidget {
  final bool addBorder;
  final double borderRadius;
  final double iconWidth;
  final double iconHeight;
  const NoThumbnailWidget({
    this.addBorder = true,
    this.borderRadius = 1,
    this.iconWidth = 35,
    this.iconHeight = 20,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: addBorder
            ? Border.all(color: colors.strokeFaint, width: 1)
            : null,
        color: colors.fillLight,
      ),
      child: Center(
        child: SvgPicture.asset(
          "assets/icons/album_empty_thumbnail.svg",
          width: iconWidth,
          height: iconHeight,
          colorFilter: ColorFilter.mode(colors.textLightest, BlendMode.srcIn),
        ),
      ),
    );
  }
}
