import 'package:ente_components/theme/icon_sizes.dart';
import 'package:ente_components/theme/radii.dart';
import 'package:ente_components/theme/spacing.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

enum BannerComponentState { failure, informative, success, warning, neutral }

/// Layout Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=14590-125265&m=dev
/// State Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=7255-38447&m=dev
/// Section: Home gallery banners / Snack bar states
/// Specs: 351px wide, 66px min height, 20px radius, 24px leading icon,
/// body/mini text, and an optional trailing action.
class BannerComponent extends StatelessWidget {
  const BannerComponent({
    required this.title,
    required this.onTap,
    this.leadingIcon,
    this.leadingWidget,
    this.state = BannerComponentState.neutral,
    this.subtitle,
    this.trailingWidget,
    super.key,
  });

  static const double minHeight = 66;
  static const double actionSize = 38;
  static const double _leadingIconSize = IconSizes.medium;
  static const double _actionIconSize = IconSizes.medium;

  final String title;
  final String? subtitle;
  final List<List<dynamic>>? leadingIcon;
  final Widget? leadingWidget;
  final BannerComponentState state;
  final Widget? trailingWidget;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final accentColor = switch (state) {
      BannerComponentState.failure => colors.warning,
      BannerComponentState.informative => colors.blue,
      BannerComponentState.success => colors.primaryDark,
      BannerComponentState.warning => colors.caution,
      BannerComponentState.neutral => colors.primaryDark,
    };
    final titleColor = switch (state) {
      BannerComponentState.failure => colors.warning,
      BannerComponentState.informative => colors.blue,
      BannerComponentState.success => colors.primaryDark,
      BannerComponentState.warning => colors.caution,
      BannerComponentState.neutral => colors.textBase,
    };
    final subtitle = this.subtitle;
    final leadingWidget = this.leadingWidget;
    final trailingWidget = this.trailingWidget;

    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: minHeight),
            child: DecoratedBox(
              key: const ValueKey('banner-component-surface'),
              decoration: BoxDecoration(
                color: colors.fillLight,
                borderRadius: BorderRadius.circular(Radii.button),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.lg,
                  vertical: Spacing.md,
                ),
                child: Row(
                  children: [
                    leadingWidget == null
                        ? HugeIcon(
                            icon: leadingIcon ?? _defaultLeadingIcon,
                            size: _leadingIconSize,
                            color: accentColor,
                          )
                        : SizedBox(
                            width: _leadingIconSize,
                            height: _leadingIconSize,
                            child: Center(
                              child: IconTheme.merge(
                                data: IconThemeData(
                                  color: accentColor,
                                  size: _leadingIconSize,
                                ),
                                child: leadingWidget,
                              ),
                            ),
                          ),
                    const SizedBox(width: Spacing.lg),
                    Expanded(
                      child: subtitle == null || subtitle.isEmpty
                          ? Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyles.bodyBold.copyWith(
                                color: titleColor,
                              ),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyles.bodyBold.copyWith(
                                    color: titleColor,
                                  ),
                                ),
                                const SizedBox(height: Spacing.xs),
                                Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyles.mini.copyWith(
                                    color: colors.textLight,
                                  ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(width: Spacing.md),
                    trailingWidget == null
                        ? _BannerActionButton(
                            iconColor: colors.textBase,
                            onTap: onTap,
                          )
                        : SizedBox(
                            key: const ValueKey(
                              'banner-component-trailing-slot',
                            ),
                            width: actionSize,
                            height: actionSize,
                            child: Center(
                              child: IconTheme.merge(
                                data: IconThemeData(
                                  color: colors.textBase,
                                  size: _actionIconSize,
                                ),
                                child: trailingWidget,
                              ),
                            ),
                          ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<List<dynamic>> get _defaultLeadingIcon {
    return switch (state) {
      BannerComponentState.failure => HugeIcons.strokeRoundedCancelCircle,
      BannerComponentState.informative => HugeIcons.strokeRoundedAlertCircle,
      BannerComponentState.success => HugeIcons.strokeRoundedCheckmarkCircle02,
      BannerComponentState.warning => HugeIcons.strokeRoundedAlert02,
      BannerComponentState.neutral => HugeIcons.strokeRoundedLoading03,
    };
  }
}

class _BannerActionButton extends StatelessWidget {
  const _BannerActionButton({required this.iconColor, required this.onTap});

  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: BannerComponent.actionSize,
        height: BannerComponent.actionSize,
        child: Center(
          child: Icon(
            Icons.arrow_forward,
            size: BannerComponent._actionIconSize,
            color: iconColor,
          ),
        ),
      ),
    );
  }
}
