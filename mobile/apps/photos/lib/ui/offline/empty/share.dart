import "package:flutter/material.dart";
import "package:photos/models/collection/collection_items.dart";
import "package:photos/theme/ente_theme.dart";

class EmptySharedSection extends StatelessWidget {
  final SharedCollections collections;

  const EmptySharedSection({super.key, required this.collections});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final total =
        collections.incoming.length +
        collections.outgoing.length +
        collections.quickLinks.length;
    final countText = total == 0
        ? "No shared albums available offline."
        : "You have $total shared album"
              "${total == 1 ? "" : "s"} on Ente.";

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.fillFaint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.strokeFaint),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Offline mode",
            style: textTheme.smallBold.copyWith(color: colorScheme.textMuted),
          ),
          const SizedBox(height: 8),
          Text(
            countText,
            style: textTheme.body.copyWith(color: colorScheme.textBase),
          ),
          const SizedBox(height: 6),
          Text(
            "Connect and sign in to see shared albums.",
            style: textTheme.small.copyWith(color: colorScheme.textMuted),
          ),
        ],
      ),
    );
  }
}
