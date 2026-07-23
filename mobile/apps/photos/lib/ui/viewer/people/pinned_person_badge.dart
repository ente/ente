import "dart:math" as math;

import "package:flutter/material.dart";
import "package:photos/theme/ente_theme.dart";

class PinnedPersonBadge extends StatelessWidget {
  const PinnedPersonBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colorScheme.backgroundElevated2,
        border: Border.all(color: colorScheme.backgroundElevated, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Transform.rotate(
        angle: -math.pi / 4,
        child: Icon(Icons.push_pin, size: 14, color: colorScheme.primary500),
      ),
    );
  }
}
