import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';

/// Auth-local selection action composed from Ente design tokens.
class AuthSelectionActionButton extends StatelessWidget {
  const AuthSelectionActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
    this.semanticsIdentifier,
  });

  final String label;
  final Widget icon;
  final VoidCallback onTap;
  final bool isDestructive;
  final String? semanticsIdentifier;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final foreground = isDestructive ? colors.warning : colors.textBase;

    return Semantics(
      button: true,
      label: label,
      identifier: semanticsIdentifier,
      child: Material(
        color: colors.fillLight,
        borderRadius: BorderRadius.circular(Radii.sheet),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Spacing.sm,
              vertical: Spacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ColorFiltered(
                  colorFilter: ColorFilter.mode(foreground, BlendMode.srcIn),
                  child: SizedBox.square(
                    dimension: IconSizes.medium,
                    child: Center(child: icon),
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyles.mini.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
