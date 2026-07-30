import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/viewer/search/search_map_navigation.dart";

//Used for empty state of location section
class GoToMap extends StatelessWidget {
  const GoToMap({super.key});

  @override
  Widget build(BuildContext context) {
    final mapTileAsset = EnteTheme.isDark(context)
        ? "assets/search_map_tile_dark.png"
        : "assets/search_map_tile_light.png";
    return GestureDetector(
      onTap: () => openSearchMap(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            ClipOval(
              child: Image.asset(
                mapTileAsset,
                width: 66.5,
                height: 66.5,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              AppLocalizations.of(context).yourMap,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: getEnteTextTheme(context).mini,
            ),
          ],
        ),
      ),
    );
  }
}
