import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_map/flutter_map.dart";
import "package:latlong2/latlong.dart";
import "package:logging/logging.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/location/location.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/files_service.dart";
import "package:photos/theme/effects.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/map/map_button.dart";
import "package:photos/ui/map/tile/layers.dart";
import "package:photos/ui/notification/toast.dart";

class UpdateLocationDataWidget extends StatefulWidget {
  final List<EnteFile> files;
  const UpdateLocationDataWidget(this.files, {super.key});

  @override
  State<UpdateLocationDataWidget> createState() =>
      _UpdateLocationDataWidgetState();
}

class _UpdateLocationDataWidgetState extends State<UpdateLocationDataWidget> {
  final MapController _mapController = MapController();
  ValueNotifier hasSelectedLocation = ValueNotifier(false);
  final selectedLocation = ValueNotifier<LatLng?>(null);
  final isDragging = ValueNotifier(false);

  @override
  void dispose() {
    super.dispose();
    hasSelectedLocation.dispose();
    selectedLocation.dispose();
    _mapController.dispose();
    isDragging.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Logger("UpdateLocationDataWiget").info("building");
    final textTheme = getEnteTextTheme(context);
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            interactionOptions: const InteractionOptions(
              enableMultiFingerGestureRace: true,
            ),
            backgroundColor: const Color.fromARGB(255, 246, 246, 246),
            initialZoom: 3,
            maxZoom: 18.0,
            minZoom: 2.8,
            onMapEvent: (p0) {
              if (p0.source == MapEventSource.onDrag) {
                isDragging.value = true;
              } else if (p0.source == MapEventSource.dragEnd) {
                isDragging.value = false;
              }
            },
            onTap: (tapPosition, latlng) {
              final zoom = selectedLocation.value == null
                  ? _mapController.camera.zoom + 2.0
                  : _mapController.camera.zoom;
              _mapController.move(latlng, zoom);

              selectedLocation.value = latlng;
              hasSelectedLocation.value = true;
            },
            onPositionChanged: (position, hasGesture) {
              if (selectedLocation.value != null) {
                selectedLocation.value = position.center;
              }
            },
          ),
          children: const [OSMTileLayer(), OSMTileAttributes()],
        ),
        Positioned(
          top: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: getEnteColorScheme(context).backgroundElevated,
              boxShadow: shadowFloatFaintLight,
            ),
            child: ValueListenableBuilder(
              valueListenable: selectedLocation,
              builder: (context, value, _) {
                final locationInDMS = locationService.convertLocationToDMS(
                  Location(
                    latitude: value?.latitude,
                    longitude: value?.longitude,
                  ),
                );
                return locationInDMS != null
                    ? ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: MediaQuery.textScalerOf(context).scale(80),
                        ),
                        child: Column(
                          children: [
                            Text(locationInDMS[0], style: textTheme.mini),
                            const SizedBox(height: 8),
                            Text(locationInDMS[1], style: textTheme.mini),
                          ],
                        ),
                      )
                    : const UpdateLocationInfo();
              },
            ),
          ),
        ),
        Positioned(
          bottom: 48,
          right: 24,
          left: 24,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MapButton(
                icon: Icons.add,
                onPressed: () {
                  _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom + 1,
                  );
                },
                heroTag: 'zoom-in',
              ),
              const SizedBox(height: 8),
              MapButton(
                icon: Icons.remove,
                onPressed: () {
                  _mapController.move(
                    _mapController.camera.center,
                    _mapController.camera.zoom - 1,
                  );
                },
                heroTag: 'zoom-out',
              ),
              const SizedBox(height: 8),
              MapButton(
                icon: Icons.check,
                onPressed: () async {
                  if (selectedLocation.value == null) {
                    showShortToast(
                      context,
                      AppLocalizations.of(context).selectALocationFirst,
                    );
                    return;
                  }
                  await FilesService.instance.bulkEditLocationData(
                    widget.files,
                    selectedLocation.value!,
                    context,
                  );
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                },
                heroTag: 'add-location',
              ),
            ],
          ),
        ),
        ValueListenableBuilder(
          valueListenable: hasSelectedLocation,
          builder: (context, value, _) {
            return value
                ? Positioned(
                    bottom: 32,
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        ValueListenableBuilder(
                          valueListenable: isDragging,
                          builder: (context, value, child) {
                            return AnimatedContainer(
                              curve: Curves.easeInOut,
                              duration: const Duration(milliseconds: 200),
                              height: value ? 32 : 16,
                              child: child,
                            );
                          },
                          child: const Icon(
                            Icons.location_on,
                            color: Color.fromARGB(255, 250, 34, 19),
                            size: 32,
                          ),
                        ),
                        Transform(
                          transform: Matrix4.translationValues(0, 21, 0),
                          child: Container(
                            height: 2,
                            width: 12,
                            decoration: BoxDecoration(
                              boxShadow: shadowMenuDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink();
          },
        ),
      ],
    );
  }
}

class UpdateLocationInfo extends StatefulWidget {
  const UpdateLocationInfo({super.key});

  @override
  State<UpdateLocationInfo> createState() => _UpdateLocationInfoState();
}

class _UpdateLocationInfoState extends State<UpdateLocationInfo> {
  bool showSelectLocationText = false;

  @override
  initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) {
        return;
      }
      setState(() {
        showSelectLocationText = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedCrossFade(
      duration: const Duration(milliseconds: 200),
      firstCurve: Curves.easeInOutExpo,
      secondCurve: Curves.easeInOutExpo,
      sizeCurve: Curves.easeInOutExpo,
      crossFadeState: showSelectLocationText
          ? CrossFadeState.showFirst
          : CrossFadeState.showSecond,
      firstChild: Text(
        AppLocalizations.of(context).selectALocation,
        style: getEnteTextTheme(context).mini,
      ),
      secondChild: Text(
        AppLocalizations.of(context).editsToLocationWillOnlyBeSeenWithinEnte,
        style: getEnteTextTheme(context).mini,
      ),
      layoutBuilder: (topChild, topChildKey, bottomChild, bottomChildKey) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: 0,
              key: bottomChildKey,
              child: bottomChild,
              // top: 0,
            ),
            Positioned(key: topChildKey, child: topChild),
          ],
        );
      },
    );
  }
}
