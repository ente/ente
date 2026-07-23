import "package:ente_components/ente_components.dart";
import "package:flutter/widgets.dart";

class EmptyStateBulletFeatureRow extends StatelessWidget {
  const EmptyStateBulletFeatureRow({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 5,
          height: 20,
          child: Align(
            alignment: Alignment.center,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
              ),
              child: const SizedBox.square(dimension: 4),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyles.body.copyWith(color: colors.textLight),
          ),
        ),
      ],
    );
  }
}
