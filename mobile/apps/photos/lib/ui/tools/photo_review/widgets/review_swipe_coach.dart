import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:photos/ui/tools/photo_review/widgets/review_swipe_stack.dart";

// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/ENTE-VISUAL-DESIGN?node-id=20419-127644&m=dev
class ReviewSwipeCoach extends StatelessWidget {
  const ReviewSwipeCoach({
    required this.direction,
    required this.bottomInset,
    required this.onTap,
    super.key,
  });

  static const double _gradientHeight = 346;

  final ReviewSwipeDirection direction;
  final double bottomInset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final l10n = context.strings;
    final isRight = direction == ReviewSwipeDirection.right;
    final label = isRight ? l10n.swipeRightToKeep : l10n.swipeLeftToDelete;
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: _gradientHeight,
          child: Semantics(
            button: true,
            label: label,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xCC000000)],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: bottomInset,
          child: IgnorePointer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  isRight
                      ? "assets/photo_review/swipe_right.svg"
                      : "assets/photo_review/swipe_left.svg",
                  width: 64,
                  height: 64,
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyles.display2.copyWith(
                      color: colors.specialWhite,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
