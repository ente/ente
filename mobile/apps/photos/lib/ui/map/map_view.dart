import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:flutter_map/flutter_map.dart";
import "package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart";
import "package:latlong2/latlong.dart";
import "package:maps_launcher/maps_launcher.dart";
import "package:photos/ui/map/image_marker.dart";
import "package:photos/ui/map/map_button.dart";
import "package:photos/ui/map/map_gallery_tile.dart";
import "package:photos/ui/map/map_gallery_tile_badge.dart";
import "package:photos/ui/map/map_marker.dart";
import "package:photos/ui/map/tile/layers.dart";

class MapView extends StatefulWidget {
  final List<ImageMarker> imageMarkers;
  final Function updateVisibleImages;
  final MapController controller;
  final LatLng center;
  final double minZoom;
  final double maxZoom;
  final double initialZoom;
  final double bottomSheetDraggableAreaHeight;
  final bool showControls;
  final int interactiveFlags;
  final VoidCallback? onTap;
  final Size markerSize;
  final MapAttributionOptions mapAttributionOptions;
  static const defaultMarkerSize = Size(75, 75);

  const MapView({
    super.key,
    required this.updateVisibleImages,
    required this.imageMarkers,
    required this.controller,
    required this.center,
    required this.minZoom,
    required this.maxZoom,
    required this.initialZoom,
    required this.bottomSheetDraggableAreaHeight,
    this.mapAttributionOptions = const MapAttributionOptions(),
    this.markerSize = MapView.defaultMarkerSize,
    this.onTap,
    this.interactiveFlags = InteractiveFlag.all,
    this.showControls = true,
  });

  @override
  State<StatefulWidget> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  late List<Marker> _markers;
  final _debouncer = Debouncer(
    const Duration(milliseconds: 300),
    executionInterval: const Duration(milliseconds: 750),
  );

  @override
  void initState() {
    super.initState();
    _markers = _buildMakers();
  }

  void onChange(LatLngBounds bounds) {
    _debouncer.run(() async {
      widget.updateVisibleImages(bounds);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: widget.controller,
          options: MapOptions(
            onTap: widget.onTap != null
                ? (_, _) {
                    widget.onTap!.call();
                  }
                : null,
            initialCenter: widget.center,
            backgroundColor: const Color.fromARGB(255, 246, 246, 246),
            minZoom: widget.minZoom,
            maxZoom: widget.maxZoom,
            interactionOptions: InteractionOptions(
              flags: widget.interactiveFlags,
              enableMultiFingerGestureRace: true,
            ),
            initialZoom: widget.initialZoom,
            cameraConstraint: CameraConstraint.contain(
              bounds: LatLngBounds(
                const LatLng(-90, -180),
                const LatLng(90, 180),
              ),
            ),
            onPositionChanged: (position, hasGesture) {
              onChange(position.visibleBounds);
            },
          ),
          children: [
            const OSMTileLayer(),
            MarkerClusterLayerWidget(
              options: MarkerClusterLayerOptions(
                alignment: Alignment.topCenter,
                maxClusterRadius: 100,
                showPolygon: false,
                spiderfyCluster: false,
                size: widget.markerSize,
                padding: const EdgeInsets.all(80),
                markers: _markers,
                onClusterTap: (_) {
                  onChange(widget.controller.camera.visibleBounds);
                },
                builder: (context, List<Marker> markers) {
                  final valueKey = markers.first.key as ValueKey;
                  final index = valueKey.value as int;

                  final clusterKey = 'map-badge-$index-len-${markers.length}';

                  return Stack(
                    key: ValueKey(clusterKey),
                    children: [
                      MapGalleryTile(
                        key: Key(markers.first.key.toString()),
                        imageMarker: widget.imageMarkers[index],
                      ),
                      MapGalleryTileBadge(size: markers.length),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                bottom: widget.bottomSheetDraggableAreaHeight,
              ),
              child: OSMTileAttributes(options: widget.mapAttributionOptions),
            ),
          ],
        ),
        widget.showControls
            ? Positioned(
                top: 4,
                left: 10,
                child: SafeArea(
                  child: MapButton(
                    icon: Icons.arrow_back,
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    heroTag: 'back',
                  ),
                ),
              )
            : const SizedBox.shrink(),
        widget.showControls
            ? Positioned(
                top: 4,
                right: 10,
                child: SafeArea(
                  child: MapButton(
                    icon: Icons.navigation_outlined,
                    onPressed: () {
                      MapsLauncher.launchCoordinates(
                        widget.controller.camera.center.latitude,
                        widget.controller.camera.center.longitude,
                      );
                    },
                    heroTag: 'open-map',
                  ),
                ),
              )
            : const SizedBox.shrink(),
        widget.showControls
            ? Positioned(
                bottom: widget.bottomSheetDraggableAreaHeight + 10,
                right: 10,
                child: Column(
                  children: [
                    MapButton(
                      icon: Icons.add,
                      onPressed: () {
                        widget.controller.move(
                          widget.controller.camera.center,
                          widget.controller.camera.zoom + 1,
                        );
                      },
                      heroTag: 'zoom-in',
                    ),
                    MapButton(
                      icon: Icons.remove,
                      onPressed: () {
                        widget.controller.move(
                          widget.controller.camera.center,
                          widget.controller.camera.zoom - 1,
                        );
                      },
                      heroTag: 'zoom-out',
                    ),
                  ],
                ),
              )
            : const SizedBox.shrink(),
      ],
    );
  }

  List<Marker> _buildMakers() {
    return List<Marker>.generate(widget.imageMarkers.length, (index) {
      final imageMarker = widget.imageMarkers[index];
      return mapMarker(
        imageMarker,
        ValueKey(index),
        markerSize: widget.markerSize,
      );
    });
  }
}
