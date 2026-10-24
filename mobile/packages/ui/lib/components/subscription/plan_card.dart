import 'package:ente_components/theme/radii.dart';
import 'package:ente_components/theme/spacing.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';

class SubscriptionPlanCard extends StatelessWidget {
  const SubscriptionPlanCard({
    super.key,
    required this.value,
    required this.unit,
    required this.includedAllowance,
    required this.price,
    this.isSelected = false,
    this.isFree = false,
    this.badgeLabel,
  });

  static const double height = 96;
  static const Color _selectionDepth = Color(0xFF009B18);
  static const Color _selectionStroke = Color(0xFF46E35E);
  static const Color _badgeColor = Color(0xFFFFD525);
  static const Color _badgeHighlight = Color(0xFFFFEFAD);
  static const Color _outline = Color(0xFF171717);

  final String value;
  final String unit;
  final Widget includedAllowance;
  final Widget price;
  final bool isSelected;
  final bool isFree;
  final String? badgeLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final hasBadge = badgeLabel != null;
    final foreground = isSelected ? colors.specialWhite : colors.textBase;
    final allowanceSize = isSelected
        ? 46.4522
        : isFree
        ? 36.9512
        : 36.0;
    final unitSize = allowanceSize * 4 / 9;
    final allowanceLineHeight = allowanceSize * 7 / 9;
    final topInset = hasBadge
        ? MediaQuery.textScalerOf(context).scale(22)
        : isSelected
        ? 6.0
        : 0.0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (isSelected)
          for (final layer in [(16.0, 1.0, 3.0), (17.0, 10.0, 2.0)])
            Positioned.fill(
              top: topInset - 22 + layer.$1,
              left: -6,
              right: -6,
              bottom: layer.$2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _selectionDepth,
                  border: Border.all(
                    color: _outline,
                    width: layer.$3,
                    strokeAlign: BorderSide.strokeAlignCenter,
                  ),
                  borderRadius: BorderRadius.circular(27),
                ),
              ),
            ),
        Padding(
          padding: EdgeInsets.only(top: topInset, bottom: isSelected ? 16 : 0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isSelected ? colors.green : colors.fillLight,
              borderRadius: BorderRadius.circular(Radii.button),
              border: Border.all(
                color: isSelected ? _selectionStroke : colors.strokeDark,
                width: isSelected ? 4.7878 : 3,
                strokeAlign: BorderSide.strokeAlignOutside,
              ),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: height),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.xl,
                  vertical: Spacing.md,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final allowance = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text.rich(
                          TextSpan(
                            style: TextStyles.display1.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.w700,
                            ),
                            children: [
                              TextSpan(
                                text: "$value ",
                                style: TextStyle(
                                  fontSize: allowanceSize,
                                  height: allowanceLineHeight / allowanceSize,
                                  letterSpacing: -allowanceSize * 0.05,
                                ),
                              ),
                              TextSpan(
                                text: unit,
                                style: TextStyle(
                                  fontSize: unitSize,
                                  height: allowanceLineHeight / unitSize,
                                  letterSpacing: -unitSize * 0.05,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          strutStyle: StrutStyle(
                            fontFamily: TextStyles.outfitFontFamily,
                            package: TextStyles.fontPackage,
                            fontWeight: FontWeight.w700,
                            fontSize: allowanceSize,
                            height:
                                allowanceLineHeight.ceilToDouble() /
                                allowanceSize,
                            forceStrutHeight: true,
                          ),
                        ),
                        const SizedBox(height: Spacing.xs),
                        includedAllowance,
                      ],
                    );
                    if (constraints.maxWidth < 260 ||
                        MediaQuery.textScalerOf(context).scale(12) > 16) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          allowance,
                          const SizedBox(height: Spacing.sm),
                          Align(alignment: Alignment.centerRight, child: price),
                        ],
                      );
                    }
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: allowance),
                        const SizedBox(width: Spacing.xs),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth / 2,
                          ),
                          child: price,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        if (hasBadge)
          Positioned(
            right: isSelected ? -9 : -4,
            top: 0,
            child: Container(
              constraints: const BoxConstraints(
                minWidth: 118,
                minHeight: 37.8867,
              ),
              padding: const EdgeInsets.fromLTRB(Spacing.md, 4, Spacing.md, 4),
              decoration: BoxDecoration(
                color: _badgeColor,
                border: Border.all(color: _outline, width: 3),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  Positioned(
                    left: -5,
                    top: -1,
                    child: Row(
                      children: [
                        _highlight(23),
                        const SizedBox(width: 2),
                        _highlight(6),
                      ],
                    ),
                  ),
                  Text(
                    badgeLabel!,
                    textAlign: TextAlign.center,
                    style: TextStyles.mini.copyWith(
                      color: _outline,
                      fontFamily: TextStyles.outfitFontFamily,
                      package: TextStyles.fontPackage,
                      fontWeight: FontWeight.w700,
                      height: 22 / 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _highlight(double width) => Container(
    width: width,
    height: 5,
    decoration: BoxDecoration(
      color: _badgeHighlight,
      borderRadius: BorderRadius.circular(2.5),
    ),
  );
}

class SubscriptionPlanList extends StatelessWidget {
  const SubscriptionPlanList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: Spacing.lg),
          children[i],
        ],
      ],
    );
  }
}
