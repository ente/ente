import "package:flutter/material.dart";
import "package:photos/theme/ente_theme.dart";

class MapButton extends StatelessWidget {
  final String heroTag;
  final IconData icon;
  final VoidCallback onPressed;

  const MapButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return FloatingActionButton(
      elevation: 2,
      heroTag: heroTag,
      highlightElevation: 3,
      backgroundColor: colorScheme.backgroundElevated,
      mini: true,
      onPressed: onPressed,
      splashColor: Colors.transparent,
      child: Icon(icon, color: colorScheme.textBase),
    );
  }
}
