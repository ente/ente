import "package:ente_components/ente_components.dart" as components;
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";

/// Pass [hugeIcon], or [iconWidget] for custom assets.
class SelectionActionButton extends StatelessWidget {
  final String labelText;
  final List<List<dynamic>>? hugeIcon;
  final Widget? iconWidget;
  final VoidCallback? onTap;
  final bool shouldShow;
  final bool isCritical;

  const SelectionActionButton({
    required this.labelText,
    required this.onTap,
    this.hugeIcon,
    this.iconWidget,
    this.shouldShow = true,
    this.isCritical = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    assert(hugeIcon != null || iconWidget != null);
    return AnimatedSize(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCirc,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: shouldShow
            ? _Body(
                labelText: labelText,
                hugeIcon: hugeIcon,
                onTap: onTap,
                iconWidget: iconWidget,
                isCritical: isCritical,
              )
            : const SizedBox(height: 60),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  final String labelText;
  final List<List<dynamic>>? hugeIcon;
  final Widget? iconWidget;
  final VoidCallback? onTap;
  final bool isCritical;
  const _Body({
    required this.labelText,
    required this.onTap,
    required this.isCritical,
    this.hugeIcon,
    this.iconWidget,
  });

  @override
  State<_Body> createState() => __BodyState();
}

class __BodyState extends State<_Body> {
  static const minWidth = 64.0;
  static const iconSize = 22.0;
  late double widthOfButton;
  Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    widthOfButton = getWidthOfButton();
    final colors = components.ComponentTheme.colorsOf(context);
    final foregroundColor = widget.isCritical
        ? colors.warning
        : colors.textBase;
    final labelStyle = components.TextStyles.mini.copyWith(
      color: foregroundColor,
    );
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (details) {
        setState(() {
          backgroundColor = colors.fillDark;
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
          borderRadius: BorderRadius.circular(16),
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
                if (widget.hugeIcon != null)
                  HugeIcon(
                    icon: widget.hugeIcon!,
                    size: iconSize,
                    color: foregroundColor,
                  )
                else
                  widget.iconWidget!,
                const SizedBox(height: 4),
                Text(
                  widget.labelText,
                  textAlign: TextAlign.center,
                  //textTheme in [getWidthOfLongestWord] should be same as this
                  style: labelStyle,
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
      final width = computeWidthOfWord(word, components.TextStyles.mini);
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
