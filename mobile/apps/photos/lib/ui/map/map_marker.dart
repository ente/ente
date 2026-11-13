import "package:flutter/material.dart";
import "package:flutter_map/flutter_map.dart";
import "package:latlong2/latlong.dart";
import "package:photos/ui/map/image_marker.dart";
import "package:photos/ui/map/map_gallery_tile_badge.dart";
import "package:photos/ui/map/map_view.dart";
import "package:photos/ui/map/marker_image.dart";
import "package:photos/ui/map/photo_map_marker.dart";

Marker mapMarker(
  ImageMarker imageMarker,
  ValueKey<int> key, {
  Size markerSize = MapView.defaultMarkerSize,
  bool useRoundedMarker = false,
  VoidCallback? onTap,
}) {
  final markerChild = useRoundedMarker
      ? PhotoMapMarker(
          file: imageMarker.imageFile,
          count: imageMarker.imageCount,
        )
      : Stack(
          children: [
            MarkerImage(
              file: imageMarker.imageFile,
              separator:
                  (MapView.defaultMarkerSize.height + 10) -
                  (MapView.defaultMarkerSize.height - markerSize.height),
            ),
            if (imageMarker.imageCount > 1)
              MapGalleryTileBadge(size: imageMarker.imageCount),
          ],
        );
  final size = useRoundedMarker ? PhotoMapMarker.markerSize : markerSize;

  return Marker(
    alignment: Alignment.topCenter,
    key: key,
    width: size.width,
    height: size.height,
    point: LatLng(imageMarker.latitude, imageMarker.longitude),
    child: onTap == null
        ? markerChild
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: markerChild,
          ),
  );
}
