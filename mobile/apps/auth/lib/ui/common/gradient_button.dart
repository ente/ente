import 'package:ente_auth/theme/ente_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:gradient_borders/box_borders/gradient_box_border.dart';

class GradientButton extends StatefulWidget {
  final Function? onTap;

  // text is ignored if child is specified
  final String text;

  // nullable
  final IconData? iconData;

  // padding between the text and icon
  final double paddingValue;

  final double fontSize;
  final double borderRadius;
  final double borderWidth;

  const GradientButton({
    super.key,
    this.onTap,
    this.text = '',
    this.iconData,
    this.paddingValue = 0.0,
    this.fontSize = 18,
    this.borderRadius = 4,
    this.borderWidth = 1,
  });

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool isTapped = false;

  @override
  Widget build(BuildContext context) {
    Widget buttonContent;
    if (widget.iconData == null) {
      buttonContent = Text(
        widget.text,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
          fontFamily: 'Inter-SemiBold',
          fontSize: widget.fontSize,
        ),
      );
    } else {
      buttonContent = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(widget.iconData, size: 20, color: Colors.white),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 6)),
          Text(
            widget.text,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontFamily: 'Inter-SemiBold',
              fontSize: widget.fontSize,
            ),
          ),
        ],
      );
    }
    final colorScheme = getEnteColorScheme(context);

    return InkWell(
      onTapDown: (_) {
        setState(() {
          isTapped = true;
        });
      },
      onTapUp: (_) {
        setState(() {
          isTapped = false;
        });
      },
      onTapCancel: () {
        setState(() {
          isTapped = false;
        });
      },
      borderRadius: BorderRadius.circular(widget.borderRadius),
      onTap: widget.onTap as void Function()?,
      child: Stack(
        children: [
          Container(
            height: 56,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              color: colorScheme.gradientButtonBgColor,
            ),
          ),
          if (!isTapped)
            ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: SvgPicture.asset(
                'assets/svg/button-tint.svg',
                fit: BoxFit.fill,
                width: double.infinity,
                height: 56,
              ),
            ),
          Container(
            height: 56,
            decoration: BoxDecoration(
              border: GradientBoxBorder(
                width: widget.borderWidth,
                gradient: LinearGradient(
                  colors: colorScheme.gradientButtonBgColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              borderRadius: BorderRadius.circular(widget.borderRadius),
            ),
            child: Center(child: buttonContent),
          ),
        ],
      ),
    );
  }
}
