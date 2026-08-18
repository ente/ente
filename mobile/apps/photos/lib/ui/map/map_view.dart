import "dart:io" show Platform;

import "package:flutter/material.dart";
import "package:flutter_map/flutter_map.dart";
import "package:latlong2/latlong.dart";
import "package:photos/ui/map/image_marker.dart";
import "package:photos/ui/map/map_button.dart";
import "package:photos/ui/map/map_marker.dart";
import "package:photos/ui/map/tile/layers.dart";
import "package:url_launcher/url_launcher.dart";

Future<bool> _launchCoordinates(double latitude, double longitude) async {
  final uri = Platform.isAndroid
      ? Uri(
          scheme: 'geo',
          host: 'ul',
          queryParameters: {'q': '$latitude,$longitude'},
        )
      : Uri.https('maps.apple.com', '/', {
          'll': '$latitude,$longitude',
          'q': '$latitude, $longitude',
        });

  final LaunchMode mode;
  if (await supportsLaunchMode(LaunchMode.externalNonBrowserApplication)) {
    mode = LaunchMode.externalNonBrowserApplication;
  } else if (await supportsLaunchMode(LaunchMode.externalApplication)) {
    mode = LaunchMode.externalApplication;
  } else {
    mode = LaunchMode.platformDefault;
  }

  return launchUrl(uri, mode: mode);
}

class MapView extends StatefulWidget {
  final List<ImageMarker> imageMarkers;
  final void Function(MapCamera camera) updateViewport;
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
    required this.updateViewport,
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

  @override
  void initState() {
    super.initState();
    _markers = _buildMarkers();
  }

  @override
  void didUpdateWidget(MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.imageMarkers, widget.imageMarkers)) {
      _markers = _buildMarkers();
    }
  }

  void onChange(MapCamera camera) {
    widget.updateViewport(camera);
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
              onChange(position);
            },
          ),
          children: [
            const OSMTileLayer(),
            MarkerLayer(markers: _markers),
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
                      _launchCoordinates(
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

  List<Marker> _buildMarkers() {
    return List<Marker>.generate(widget.imageMarkers.length, (index) {
      final imageMarker = widget.imageMarkers[index];
      final clusterBounds = imageMarker.clusterBounds;
      return mapMarker(
        imageMarker,
        ValueKey(index),
        markerSize: widget.markerSize,
        onTap: clusterBounds == null
            ? null
            : () {
                widget.controller.fitCamera(
                  CameraFit.bounds(
                    bounds: clusterBounds,
                    padding: const EdgeInsets.all(80),
                    maxZoom: widget.maxZoom,
                  ),
                );
              },
      );
    });
  }
}
