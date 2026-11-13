import "package:flutter/material.dart";
import "package:photos/theme/ente_theme.dart";

class FilterPillWidget extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const FilterPillWidget({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? colorScheme.greenBase : colorScheme.fill,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: selected
              ? textTheme.mini.copyWith(color: Colors.white)
              : textTheme.miniMuted,
        ),
      ),
    );
  }
}
