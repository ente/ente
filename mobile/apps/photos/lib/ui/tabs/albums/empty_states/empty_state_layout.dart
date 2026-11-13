import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:photos/ui/home/home_bottom_nav_bar.dart";

class EmptyStateLayout extends StatelessWidget {
  const EmptyStateLayout({
    required this.assetPath,
    required this.assetHeight,
    required this.title,
    required this.description,
    this.action,
    this.descriptionWidth = 260,
    this.reservesBottomNavigationSpace = true,
    super.key,
  });

  final String assetPath;
  final double assetHeight;
  final String title;
  final String description;
  final Widget? action;
  final double descriptionWidth;
  final bool reservesBottomNavigationSpace;

  static const _contentMaxWidth = 343.0;
  static const _textToActionSpacing = 48.0;
  static const _designBottomClearance = 52.0;
  static const _navigationClearance =
      homeBottomNavigationBarHeight + Spacing.lg;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final bottomSafeArea = MediaQuery.paddingOf(context).bottom;
    final padding = reservesBottomNavigationSpace
        ? EdgeInsets.fromLTRB(
            Spacing.lg,
            _navigationClearance - _designBottomClearance,
            Spacing.lg,
            bottomSafeArea + _navigationClearance,
          )
        : EdgeInsets.fromLTRB(Spacing.lg, 0, Spacing.lg, bottomSafeArea);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: padding,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(assetPath, height: assetHeight),
                      const SizedBox(height: Spacing.xl),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: TextStyles.display2.copyWith(
                          color: colors.textBase,
                        ),
                      ),
                      const SizedBox(height: Spacing.sm),
                      SizedBox(
                        width: descriptionWidth,
                        child: Text(
                          description,
                          textAlign: TextAlign.center,
                          style: TextStyles.body.copyWith(
                            color: colors.textLight,
                          ),
                        ),
                      ),
                      if (action != null) ...[
                        const SizedBox(height: _textToActionSpacing),
                        action!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
