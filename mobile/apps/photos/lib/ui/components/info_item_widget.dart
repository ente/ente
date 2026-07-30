import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import 'package:photos/ui/components/buttons/icon_button_widget.dart';

///https://www.figma.com/file/SYtMyLBs5SAOkTbfMMzhqt/ente-Visual-Design?node-id=8113-59605&t=OMX5f5KdDJYWSQQN-4
class InfoItemWidget extends StatelessWidget {
  final IconData? leadingIcon;
  final Widget? leadingIconWidget;
  final VoidCallback? editOnTap;
  final String? title;
  final Widget? endSection;
  final FutureOr<List<Widget>> subtitleSection;
  final bool hasChipButtons;
  final bool biggerSpinner;
  final VoidCallback? onTap;
  final bool useMenuStyle;
  const InfoItemWidget({
    this.leadingIcon,
    this.leadingIconWidget,
    this.editOnTap,
    this.title,
    this.endSection,
    required this.subtitleSection,
    this.hasChipButtons = false,
    this.biggerSpinner = false,
    this.onTap,
    this.useMenuStyle = false,
    super.key,
  }) : assert(leadingIcon != null || leadingIconWidget != null);

  @override
  Widget build(BuildContext context) {
    if (useMenuStyle) {
      return _buildMenuStyle(context);
    }

    final children = <Widget>[];
    if (title != null) {
      children.addAll([
        Text(
          title!,
          style: hasChipButtons
              ? getEnteTextTheme(context).miniMuted
              : getEnteTextTheme(context).small,
        ),
        SizedBox(height: hasChipButtons ? 8 : 4),
      ]);
    }

    children.addAll([
      Flexible(
        child: _buildSubtitleSection(context, (context, snapshot) {
          Widget child;
          if (snapshot.hasData) {
            final subtitle = snapshot.data as List<Widget>;
            if (subtitle.isNotEmpty) {
              child = Wrap(runSpacing: 8, spacing: 8, children: subtitle);
            } else {
              child = const SizedBox.shrink();
            }
          } else {
            child = EnteLoadingWidget(
              padding: biggerSpinner ? 6 : 3,
              size: biggerSpinner ? 20 : 11,
              color: getEnteColorScheme(context).strokeMuted,
              alignment: biggerSpinner
                  ? Alignment.center
                  : Alignment.centerLeft,
            );
          }
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeInOutExpo,
            child: child,
          );
        }),
      ),
    ]);

    endSection != null ? children.add(endSection!) : null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButtonWidget(
                icon: leadingIcon,
                iconWidget: leadingIconWidget,
                iconButtonType: IconButtonType.secondary,
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 3.5, 16, 3.5),
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: onTap,
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: children,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        editOnTap != null
            ? IconButtonWidget(
                icon: Icons.edit,
                iconButtonType: IconButtonType.secondary,
                onTap: editOnTap,
              )
            : const SizedBox.shrink(),
      ],
    );
  }

  Widget _buildMenuStyle(BuildContext context) {
    final colors = context.componentColors;
    final leading = leadingIconWidget ?? Icon(leadingIcon);

    return Material(
      color: colors.fillLight,
      borderRadius: BorderRadius.circular(Radii.button),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Radii.button),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 54),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.md,
                  9,
                  Spacing.md,
                  9,
                ),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 36,
                      child: Center(
                        child: IconTheme.merge(
                          data: IconThemeData(
                            color: colors.textLight,
                            size: IconSizes.small,
                          ),
                          child: leading,
                        ),
                      ),
                    ),
                    const SizedBox(width: Spacing.md),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (title != null) ...[
                            Text(
                              title!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyles.body.copyWith(
                                color: colors.textBase,
                              ),
                            ),
                            const SizedBox(height: Spacing.xs),
                          ],
                          _buildSubtitleSection(context, (context, snapshot) {
                            final Widget child;
                            if (snapshot.hasData) {
                              final subtitle = snapshot.data!;
                              child = subtitle.isEmpty
                                  ? const SizedBox.shrink()
                                  : Wrap(
                                      runSpacing: Spacing.sm,
                                      spacing: hasChipButtons
                                          ? Spacing.sm
                                          : Spacing.md,
                                      children: subtitle,
                                    );
                            } else {
                              child = EnteLoadingWidget(
                                padding: biggerSpinner ? 6 : 3,
                                size: biggerSpinner ? 20 : 11,
                                color: colors.strokeFaint,
                                alignment: biggerSpinner
                                    ? Alignment.center
                                    : Alignment.centerLeft,
                              );
                            }
                            return AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              switchInCurve: Curves.easeInOutExpo,
                              child: child,
                            );
                          }),
                        ],
                      ),
                    ),
                    if (editOnTap != null) ...[
                      const SizedBox(width: Spacing.md),
                      IconButtonComponent(
                        icon: HugeIcon(
                          icon: HugeIcons.strokeRoundedEdit03,
                          size: IconSizes.small,
                          color: colors.textLight,
                        ),
                        variant: IconButtonComponentVariant.secondary,
                        shouldSurfaceExecutionStates: false,
                        onTap: editOnTap,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (endSection != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.md,
                0,
                Spacing.md,
                Spacing.md,
              ),
              child: endSection!,
            ),
        ],
      ),
    );
  }

  Widget _buildSubtitleSection(
    BuildContext context,
    AsyncWidgetBuilder<List<Widget>> builder,
  ) {
    final section = subtitleSection;
    if (section is List<Widget>) {
      return builder(
        context,
        AsyncSnapshot.withData(ConnectionState.done, section),
      );
    }

    return FutureBuilder<List<Widget>>(future: section, builder: builder);
  }
}
