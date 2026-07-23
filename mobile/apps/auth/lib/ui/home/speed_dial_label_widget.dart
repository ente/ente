import 'package:ente_auth/ente_theme_data.dart';
import 'package:flutter/material.dart';

class SpeedDialLabelWidget extends StatelessWidget {
  final String label;

  const SpeedDialLabelWidget(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(1)),
      child: Container(
        margin: const EdgeInsets.all(4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.fabBackgroundColor,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Theme.of(context).colorScheme.fabForegroundColor,
          ),
        ),
      ),
    );
  }
}
