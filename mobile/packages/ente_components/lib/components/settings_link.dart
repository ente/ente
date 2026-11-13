import 'package:ente_components/theme/spacing.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

class SettingsLink extends StatelessWidget {
  const SettingsLink({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm,
          vertical: Spacing.md,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyles.bodyBold.copyWith(color: colors.primary),
            ),
            const SizedBox(width: Spacing.xs),
            HugeIcon(
              icon: HugeIcons.strokeRoundedArrowRight01,
              color: colors.primary,
              size: 16,
              strokeWidth: 1.6,
            ),
          ],
        ),
      ),
    );
  }
}
