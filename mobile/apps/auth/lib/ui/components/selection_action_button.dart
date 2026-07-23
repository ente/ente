import 'dart:math' as math;

import "package:ente_auth/theme/ente_theme.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/svg.dart";

/// Pass icon or asset path of svg
class SelectionActionButton extends StatelessWidget {
  final String labelText;
  final IconData? icon;
  final String? svgAssetPath;
  final VoidCallback? onTap;
  final bool shouldShow;

  const SelectionActionButton({
    required this.labelText,
    required this.onTap,
    this.icon,
    this.svgAssetPath,
    this.shouldShow = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    assert(icon != null || svgAssetPath != null);
    return AnimatedSize(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCirc,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: shouldShow
            ? _Body(
                labelText: labelText,
                icon: icon,
                onTap: onTap,
                svgAssetPath: svgAssetPath,
              )
            : const SizedBox(height: 60),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  final String labelText;
  final IconData? icon;
  final String? svgAssetPath;
  final VoidCallback? onTap;
  const _Body({
    required this.labelText,
    required this.onTap,
    this.icon,
    this.svgAssetPath,
  });

  @override
  State<_Body> createState() => __BodyState();
}

class __BodyState extends State<_Body> {
  static const minWidth = 64.0;
  late double widthOfButton;
  Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    widthOfButton = getWidthOfButton();
    final colorScheme = getEnteColorScheme(context);
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (details) {
        setState(() {
          backgroundColor = colorScheme.fillFaintPressed;
        });
      },
      onTapUp: (details) {
        setState(() {
          backgroundColor = null;
        });
      },
      onTapCancel: () {
        setState(() {
          backgroundColor = null;
        });
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: backgroundColor,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
          child: SizedBox(
            width: widthOfButton,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon == Icons.navigation_rounded)
                  Transform.rotate(
                    angle: math.pi / 2,
                    child: Icon(
                      widget.icon,
                      size: 24,
                      color: getEnteColorScheme(context).primary300,
                      shadows: const [
                        BoxShadow(
                          color: Color.fromARGB(12, 0, 179, 60),
                          offset: Offset(0, 2.51),
                          blurRadius: 5.02,
                          spreadRadius: 0,
                        ),
                        BoxShadow(
                          color: Color.fromARGB(24, 0, 179, 60),
                          offset: Offset(0, 1.25),
                          blurRadius: 3.76,
                          spreadRadius: 0,
                        ),
                        BoxShadow(
                          color: Color.fromARGB(24, 0, 179, 60),
                          offset: Offset(0, 0.63),
                          blurRadius: 1.88,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                  )
                else
                  widget.svgAssetPath != null
                      ? SvgPicture.asset(
                          widget.svgAssetPath!,
                          colorFilter: ColorFilter.mode(
                            getEnteColorScheme(context).textMuted,
                            BlendMode.srcIn,
                          ),
                          width: 24,
                          height: 24,
                        )
                      : Icon(
                          widget.icon,
                          size: 24,
                          color: getEnteColorScheme(context).textMuted,
                        ),
                const SizedBox(height: 4),
                Text(
                  widget.labelText,
                  textAlign: TextAlign.center,
                  //textTheme in [getWidthOfLongestWord] should be same as this
                  style: getEnteTextTheme(context).miniMuted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  double getWidthOfButton() {
    final widthOfWidestWord = getWidthOfWidestWord(widget.labelText);
    if (widthOfWidestWord > minWidth) return widthOfWidestWord;
    return minWidth;
  }

  double getWidthOfWidestWord(String labelText) {
    final words = labelText.split(RegExp(r'\s+'));
    if (words.isEmpty) return 0.0;

    double maxWidth = 0.0;
    for (String word in words) {
      final width = computeWidthOfWord(
        word,
        getEnteTextTheme(context).miniMuted,
      );
      if (width > maxWidth) {
        maxWidth = width;
      }
    }
    return maxWidth;
  }

  //Todo: this doesn't give the correct width of the word, make it right
  double computeWidthOfWord(String text, TextStyle style) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    //buffer of 8 added as width is shorter than actual text width
    return textPainter.size.width + 8;
  }
}
