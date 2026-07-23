import 'package:flutter/material.dart';
import 'package:photos/ente_theme_data.dart';
import "package:photos/generated/l10n.dart";

class EmptyState extends StatelessWidget {
  final String? text;

  const EmptyState({super.key, this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text(
          text ?? AppLocalizations.of(context).nothingToSeeHere,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.defaultTextColor.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }
}
