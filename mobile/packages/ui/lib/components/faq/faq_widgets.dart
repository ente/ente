import 'dart:async';

import 'package:ente_components/components/navigation_card_component.dart';
import 'package:ente_components/theme/icon_sizes.dart';
import 'package:ente_components/theme/motion.dart';
import 'package:ente_components/theme/radii.dart';
import 'package:ente_components/theme/spacing.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

class FaqCard extends StatelessWidget {
  const FaqCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final FutureOr<void> Function() onTap;

  @override
  Widget build(BuildContext context) => NavigationCardComponent(
    title: title,
    subtitle: subtitle,
    leading: HugeIcon(
      icon: HugeIcons.strokeRoundedBubbleChatQuestion,
      size: NavigationCardComponent.leadingSize,
      color: context.componentColors.textLight,
    ),
    onTap: onTap,
  );
}

class FaqSection extends StatelessWidget {
  const FaqSection({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(height: Spacing.sm),
        children[i],
      ],
    ],
  );
}

class FaqItemWidget extends StatefulWidget {
  const FaqItemWidget({
    super.key,
    required this.question,
    required this.answer,
  });

  final String question;
  final String answer;

  @override
  State<FaqItemWidget> createState() => _FaqItemWidgetState();
}

class _FaqItemWidgetState extends State<FaqItemWidget> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Material(
      color: colors.fillLight,
      borderRadius: BorderRadius.circular(Radii.button),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.xl,
                Spacing.lg,
                Spacing.xl,
                Spacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.question,
                      style: TextStyles.bodyBold.copyWith(
                        color: colors.textBase,
                      ),
                    ),
                  ),
                  const SizedBox(width: Spacing.sm),
                  HugeIcon(
                    icon: _isExpanded
                        ? HugeIcons.strokeRoundedArrowUp01
                        : HugeIcons.strokeRoundedArrowDown01,
                    size: IconSizes.small,
                    color: colors.textBase,
                  ),
                ],
              ),
            ),
            AnimatedSize(
              duration: Motion.standard,
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: _isExpanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Spacing.xl,
                        0,
                        Spacing.xl,
                        Spacing.lg,
                      ),
                      child: Text(
                        widget.answer,
                        style: TextStyles.mini.copyWith(
                          color: colors.textLight,
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}
