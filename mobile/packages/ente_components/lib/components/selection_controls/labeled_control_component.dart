import 'package:ente_components/theme/spacing.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';

class LabeledControlComponent extends StatelessWidget {
  const LabeledControlComponent({
    super.key,
    required this.control,
    required this.label,
    this.subtitle,
    this.foreground,
    this.onTap,
  });

  final Widget control;
  final String label;
  final String? subtitle;

  /// Overrides the label and subtitle color.
  final Color? foreground;

  /// Called when the label area is tapped.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final labelContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyles.body.copyWith(color: foreground ?? colors.textBase),
        ),
        if (subtitle != null)
          Text(
            subtitle!,
            style: TextStyles.mini.copyWith(
              color: foreground ?? colors.textLight,
            ),
          ),
      ],
    );
    final tappableLabel = InkWell(onTap: onTap, child: labelContent);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        control,
        const SizedBox(width: Spacing.md),
        Flexible(child: tappableLabel),
      ],
    );
  }
}
