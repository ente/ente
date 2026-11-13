import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_map/flutter_map.dart";
import "package:photos/service_locator.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/map/tile/attribution/map_attribution.dart";
import "package:url_launcher/url_launcher.dart";
import "package:url_launcher/url_launcher_string.dart";

const _tileCacheSizeBytes = 200 * 1024 * 1024;

NetworkTileProvider get _tileProvider => NetworkTileProvider(
  headers: {'User-Agent': _userAgent},
  cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
    maxCacheSize: _tileCacheSizeBytes,
  ),
);

String get _userAgent {
  try {
    final version = ServiceLocator.instance.packageInfo.version;
    return "Ente Photos/$version (+https://ente.com; contact: team@ente.com)";
  } catch (_) {
    return "Ente Photos/unknown (+https://ente.com; contact: team@ente.com)";
  }
}

class MapAttributionOptions {
  final double permanentHeight;
  final BorderRadius popupBorderRadius;
  final double iconSize;

  const MapAttributionOptions({
    this.permanentHeight = 24,
    this.popupBorderRadius = const BorderRadius.all(Radius.circular(12)),
    this.iconSize = 20,
  });
}

class OSMTileLayer extends StatelessWidget {
  const OSMTileLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      tileProvider: _tileProvider,
    );
  }
}

class OSMFranceTileLayer extends StatelessWidget {
  const OSMFranceTileLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return TileLayer(
      urlTemplate: 'https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
      fallbackUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      subdomains: const ['a', 'b', 'c'],
      tileProvider: _tileProvider,
      panBuffer: 1,
    );
  }
}

class OSMTileAttributes extends StatelessWidget {
  final MapAttributionOptions options;
  const OSMTileAttributes({
    this.options = const MapAttributionOptions(),
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context).tinyBold;
    return MapAttributionWidget(
      alignment: AttributionAlignment.bottomLeft,
      showFlutterMapAttribution: false,
      permanentHeight: options.permanentHeight,
      popupBackgroundColor: getEnteColorScheme(context).backgroundElevated,
      popupBorderRadius: options.popupBorderRadius,
      iconSize: options.iconSize,
      attributions: [
        TextSourceAttribution(
          context.strings.openstreetmapContributors,
          textStyle: textTheme,
          onTap: () => launchUrlString('https://openstreetmap.org/copyright'),
        ),
        TextSourceAttribution(
          'HOT Tiles',
          textStyle: textTheme,
          onTap: () => launchUrl(Uri.parse('https://www.hotosm.org/')),
        ),
      ],
    );
  }
}

class OSMFranceTileAttributes extends StatelessWidget {
  final MapAttributionOptions options;
  const OSMFranceTileAttributes({
    this.options = const MapAttributionOptions(),
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context).tinyBold;
    return MapAttributionWidget(
      alignment: AttributionAlignment.bottomLeft,
      showFlutterMapAttribution: false,
      permanentHeight: options.permanentHeight,
      popupBackgroundColor: getEnteColorScheme(context).backgroundElevated,
      popupBorderRadius: options.popupBorderRadius,
      iconSize: options.iconSize,
      attributions: [
        TextSourceAttribution(
          context.strings.openstreetmapContributors,
          textStyle: textTheme,
          onTap: () => launchUrlString('https://openstreetmap.org/copyright'),
        ),
        TextSourceAttribution(
          'HOT Tiles',
          textStyle: textTheme,
          onTap: () => launchUrl(Uri.parse('https://www.hotosm.org/')),
        ),
        TextSourceAttribution(
          context.strings.hostedAtOsmFrance,
          textStyle: textTheme,
          onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.fr/')),
        ),
      ],
    );
  }
}

class MapBoxTilesLayer extends StatelessWidget {
  const MapBoxTilesLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return TileLayer(
      urlTemplate:
          "https://api.mapbox.com/styles/v1/{mb_user}/{mb_style_id}/tiles/{z}/{x}/{y}?access_token={mb_token}",
      fallbackUrl: 'https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
      subdomains: const ['a', 'b', 'c'],
      tileProvider: _tileProvider,
      additionalOptions: const {
        "mb_token": String.fromEnvironment("mb_token"),
        "mb_style_id": String.fromEnvironment("mb_style_id"),
        "mb_user": String.fromEnvironment("mb_user"),
      },
    );
  }
}
