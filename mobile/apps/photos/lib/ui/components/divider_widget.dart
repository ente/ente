import 'package:flutter/material.dart';
import 'package:photos/theme/ente_theme.dart';

enum DividerType { solid, menu, menuNoIcon, bottomBar }

class DividerWidget extends StatelessWidget {
  final DividerType dividerType;
  final Color bgColor;
  final bool divColorHasBlur;
  final EdgeInsets? padding;
  const DividerWidget({
    required this.dividerType,
    this.bgColor = Colors.transparent,
    this.divColorHasBlur = true,
    this.padding,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final dividerColor = divColorHasBlur
        ? getEnteColorScheme(context).blurStrokeFaint
        : getEnteColorScheme(context).strokeFaint;

    if (dividerType == DividerType.solid) {
      return Padding(
        padding: padding ?? EdgeInsets.zero,
        child: Container(
          color: getEnteColorScheme(context).strokeFaint,
          width: double.infinity,
          height: 1,
        ),
      );
    }
    if (dividerType == DividerType.bottomBar) {
      return Padding(
        padding: padding ?? EdgeInsets.zero,
        child: Container(
          color: dividerColor,
          width: double.infinity,
          height: 1,
        ),
      );
    }

    return Container(
      color: bgColor,
      padding: padding ?? EdgeInsets.zero,
      child: Row(
        children: [
          SizedBox(
            width: dividerType == DividerType.menu
                ? 48
                : dividerType == DividerType.menuNoIcon
                ? 16
                : 0,
            height: 1,
          ),
          Expanded(
            child: Container(
              color: dividerColor,
              height: 1,
              width: double.infinity,
            ),
          ),
        ],
      ),
    );
  }
}
