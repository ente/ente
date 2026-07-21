import "dart:async";
import "dart:ui";

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:flutter_animate/flutter_animate.dart";
import "package:flutter_map/flutter_map.dart";
import "package:hugeicons/hugeicons.dart";
import "package:latlong2/latlong.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/location_tag_updated_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/search_service.dart";
import "package:photos/states/location_screen_state.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/map/image_marker.dart";
import "package:photos/ui/map/map_screen.dart";
import "package:photos/ui/map/map_view.dart";
import "package:photos/ui/map/tile/layers.dart";
import 'package:photos/ui/notification/toast.dart';
import 'package:photos/ui/viewer/location/add_location_sheet.dart';
import "package:photos/ui/viewer/location/location_screen.dart";

class LocationTagsWidget extends StatefulWidget {
  final EnteFile file;

  const LocationTagsWidget(this.file, {super.key});

  @override
  State<LocationTagsWidget> createState() => _LocationTagsWidgetState();
}

class _LocationTagsWidgetState extends State<LocationTagsWidget> {
  String? title;
  late Future<List<Widget>> locationTagChips;
  late StreamSubscription<LocationTagUpdatedEvent> _locTagUpdateListener;
  bool _loadedLocationTags = false;

  @override
  void initState() {
    locationTagChips = _getLocationTags().then((value) {
      _loadedLocationTags = true;
      return value;
    });
    _locTagUpdateListener = Bus.instance.on<LocationTagUpdatedEvent>().listen((
      event,
    ) {
      locationTagChips = _getLocationTags();
    });

    super.initState();
  }

  @override
  void dispose() {
    _locTagUpdateListener.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title ?? AppLocalizations.of(context).location,
          style: TextStyles.h2,
        ),
        const SizedBox(height: Spacing.lg),
        FutureBuilder<List<Widget>>(
          future: locationTagChips,
          builder: (context, snapshot) {
            final Widget child;
            if (snapshot.hasData) {
              child = Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: snapshot.data!,
              );
            } else {
              child = EnteLoadingWidget(
                padding: 3,
                size: 11,
                color: colors.strokeFaint,
                alignment: Alignment.centerLeft,
              );
            }
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeInOutExpo,
              child: child,
            );
          },
        ),
        if (_loadedLocationTags) InfoMap(widget.file),
      ],
    );
  }

  Future<List<Widget>> _getLocationTags() async {
    // await Future.delayed(const Duration(seconds: 1));
    final locationTags = await locationService.enclosingLocationTags(
      widget.file.location!,
    );
    if (locationTags.isEmpty) {
      if (mounted) {
        setState(() {
          title = AppLocalizations.of(context).location;
        });
      }
      if (!mounted) return const [];
      return [
        FilterChipComponent(
          label: AppLocalizations.of(context).addLocation,
          onChanged: (_) =>
              showAddLocationSheet(context, widget.file.location!),
        ),
      ];
    } else {
      if (mounted) {
        setState(() {
          title = AppLocalizations.of(context).location;
        });
      }
      final result = locationTags
          .map<Widget>(
            (locationTagEntity) => FilterChipComponent(
              label: locationTagEntity.item.name,
              onChanged: (_) {
                routeToPage(
                  context,
                  LocationScreenStateProvider(
                    locationTagEntity,
                    const LocationScreen(),
                  ),
                );
              },
            ),
          )
          .toList();
      result.add(
        IconButtonComponent(
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedPlusSign,
            size: IconSizes.small,
          ),
          variant: IconButtonComponentVariant.circular,
          shouldSurfaceExecutionStates: false,
          onTap: () => showAddLocationSheet(context, widget.file.location!),
        ),
      );
      return result;
    }
  }
}

class InfoMap extends StatefulWidget {
  final EnteFile file;
  const InfoMap(this.file, {super.key});

  @override
  State<InfoMap> createState() => _InfoMapState();
}

class _InfoMapState extends State<InfoMap> {
  final _mapController = MapController();
  late bool _hasEnabledMap;
  late double _fileLat;
  late double _fileLng;
  static const _enabledMapZoom = 12.0;
  static const _disabledMapZoom = 9.0;
  bool _tappedToOpenMap = false;
  final _past250msAfterInit = ValueNotifier(false);

  @override
  void initState() {
    super.initState();
    _hasEnabledMap = mapEnabled;
    _fileLat = widget.file.location!.latitude!;
    _fileLng = widget.file.location!.longitude!;

    Future.delayed(const Duration(milliseconds: 250), () {
      _past250msAfterInit.value = true;
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    _past250msAfterInit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ClipRRect(
            clipBehavior: Clip.antiAliasWithSaveLayer,
            borderRadius: const BorderRadius.all(Radius.circular(Radii.button)),
            child: SizedBox(
              height: 124,
              child: _hasEnabledMap
                  ? Stack(
                      clipBehavior: Clip.none,
                      key: ValueKey(_hasEnabledMap),
                      children: [
                        MapView(
                          updateVisibleImages: () {},
                          imageMarkers: [
                            ImageMarker(
                              imageFile: widget.file,
                              latitude: _fileLat,
                              longitude: _fileLng,
                            ),
                          ],
                          controller: _mapController,
                          center: LatLng(_fileLat, _fileLng),
                          minZoom: _enabledMapZoom,
                          maxZoom: _enabledMapZoom,
                          initialZoom: _enabledMapZoom,
                          bottomSheetDraggableAreaHeight: 0,
                          showControls: false,
                          interactiveFlags: InteractiveFlag.none,
                          mapAttributionOptions: MapAttributionOptions(
                            permanentHeight: 16,
                            popupBorderRadius: BorderRadius.circular(4),
                            iconSize: 16,
                          ),
                          onTap: enabledMapOnTap,
                          markerSize: const Size(45, 45),
                        ),
                        IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(Radii.button),
                              border: Border.all(
                                color: getEnteColorScheme(context).strokeFaint,
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : ValueListenableBuilder(
                      valueListenable: _past250msAfterInit,
                      builder: (context, value, _) {
                        return value
                            ? Stack(
                                key: ValueKey(_hasEnabledMap),
                                clipBehavior: Clip.none,
                                children: [
                                  MapView(
                                    updateVisibleImages: () {},
                                    imageMarkers: const [],
                                    controller: _mapController,
                                    center: const LatLng(13.041599, 77.594566),
                                    minZoom: _disabledMapZoom,
                                    maxZoom: _disabledMapZoom,
                                    initialZoom: _disabledMapZoom,
                                    bottomSheetDraggableAreaHeight: 0,
                                    showControls: false,
                                    interactiveFlags: InteractiveFlag.none,
                                    mapAttributionOptions:
                                        const MapAttributionOptions(
                                          iconSize: 0,
                                        ),
                                  ),
                                  BackdropFilter(
                                    filter: ImageFilter.blur(
                                      sigmaX: 2.8,
                                      sigmaY: 2.8,
                                    ),
                                    child: Container(
                                      color: getEnteColorScheme(context)
                                          .backgroundElevated
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                        Radii.button,
                                      ),
                                      border: Border.all(
                                        color: getEnteColorScheme(
                                          context,
                                        ).strokeFaint,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () async {
                                      try {
                                        await setMapEnabled(true);
                                        if (!mounted) return;
                                        setState(() {
                                          _hasEnabledMap = true;
                                        });
                                      } catch (e) {
                                        if (!context.mounted) return;
                                        showShortToast(
                                          context,
                                          AppLocalizations.of(
                                            context,
                                          ).somethingWentWrong,
                                        );
                                      }
                                    },
                                    child: Center(
                                      child: Text(
                                        AppLocalizations.of(context).enableMaps,
                                        style: getEnteTextTheme(context).small,
                                      ),
                                    ),
                                  ),
                                ],
                              ).animate().fadeIn(
                                duration: const Duration(milliseconds: 90),
                                curve: Curves.easeIn,
                              )
                            : const SizedBox.shrink();
                      },
                    ),
            ),
          ),
        )
        .animate(target: _tappedToOpenMap ? 1 : 0)
        .scaleXY(
          end: 1.025,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeInOut,
        );
  }

  void enabledMapOnTap() async {
    setState(() {
      _tappedToOpenMap = true;
    });
    unawaited(
      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (context) => MapScreen(
                filesFutureFn: SearchService.instance.getAllFilesForSearch,
                center: LatLng(_fileLat, _fileLng),
                initialZoom: 16,
              ),
            ),
          )
          .then((value) {
            setState(() {
              _tappedToOpenMap = false;
            });
          }),
    );
  }
}
