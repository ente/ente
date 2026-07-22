import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";

const double fileDetailsMenuRowHeight = 60;

class FileDetailsMenuGroupNew extends StatelessWidget {
  const FileDetailsMenuGroupNew({required this.items, super.key});

  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    final isGroup = items.length > 1;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.hardEdge,
      padding: isGroup
          ? const EdgeInsets.symmetric(vertical: Spacing.sm)
          : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: context.componentColors.fillLight,
        borderRadius: BorderRadius.circular(Radii.button),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < items.length; index++) ...[
            items[index],
            if (index < items.length - 1) const SizedBox(height: Spacing.sm),
          ],
        ],
      ),
    );
  }
}
