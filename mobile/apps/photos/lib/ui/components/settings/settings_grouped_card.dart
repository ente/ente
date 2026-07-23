import "package:flutter/material.dart";

/// A container for grouped settings items.
/// Uses 20px border radius and the standard card colors.
class SettingsGroupedCard extends StatelessWidget {
  final List<Widget> children;

  const SettingsGroupedCard({required this.children, super.key});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Card background: Light #FFFFFF, Dark #212121
    final cardColor = isDarkMode
        ? const Color(0xFF212121)
        : const Color(0xFFFFFFFF);

    final childCount = children.length;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < childCount; i++)
            ClipRRect(
              borderRadius: BorderRadius.vertical(
                top: i == 0 ? const Radius.circular(20) : Radius.zero,
                bottom: i == childCount - 1
                    ? const Radius.circular(20)
                    : Radius.zero,
              ),
              child: children[i],
            ),
        ],
      ),
    );
  }
}
