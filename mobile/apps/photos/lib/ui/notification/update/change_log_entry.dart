import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';

class ChangeLogEntry {
  final bool isFeature;
  final String title;
  final String? description;
  final List<String> items;

  ChangeLogEntry(
    this.title, {
    this.description,
    this.items = const [],
    this.isFeature = true,
  });
}

class ChangeLogEntryWidget extends StatelessWidget {
  final ChangeLogEntry entry;

  const ChangeLogEntryWidget({super.key, required this.entry});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final hasDescription =
        entry.description != null && entry.description!.isNotEmpty;
    final hasItems = entry.items.isNotEmpty;
    final mutedStyle = TextStyles.body.copyWith(color: colors.textLight);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entry.title,
          textAlign: TextAlign.left,
          style: TextStyles.large.copyWith(
            color: entry.isFeature ? colors.primary : colors.textLight,
          ),
        ),
        const SizedBox(height: Spacing.sm),
        if (hasDescription)
          Padding(
            padding: EdgeInsets.only(bottom: hasItems ? Spacing.md : 0),
            child: Text(
              entry.description!,
              textAlign: TextAlign.left,
              style: mutedStyle,
            ),
          ),
        ...entry.items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: Spacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('•  ', style: mutedStyle),
                Expanded(
                  child: Text(
                    item,
                    textAlign: TextAlign.left,
                    style: mutedStyle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
