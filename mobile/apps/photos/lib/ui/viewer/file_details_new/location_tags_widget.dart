import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:flutter_map/flutter_map.dart";
import "package:hugeicons/hugeicons.dart";
import "package:latlong2/latlong.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/location_tag_updated_event.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/local_entity_data.dart";
import "package:photos/models/location_tag/location_tag.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/search_service.dart";
import "package:photos/states/location_screen_state.dart";
import "package:photos/ui/map/image_marker.dart";
import "package:photos/ui/map/map_screen.dart";
import "package:photos/ui/map/map_view.dart";
import "package:photos/ui/map/tile/layers.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/viewer/file_details_new/file_details_skeleton.dart";
import "package:photos/ui/viewer/location/add_location_sheet.dart";
import "package:photos/ui/viewer/location/location_screen.dart";

class LocationTagsWidgetNew extends StatefulWidget {
  const LocationTagsWidgetNew({
    required this.file,
    required this.mapLoadDelay,
    super.key,
  });

  final EnteFile file;
  final Duration mapLoadDelay;

  @override
  State<LocationTagsWidgetNew> createState() => _LocationTagsWidgetNewState();
}

class _LocationTagsWidgetNewState extends State<LocationTagsWidgetNew> {
  final Logger _logger = Logger("LocationTagsWidgetNew");
  List<LocalEntity<LocationTag>>? _tags;
  late final StreamSubscription<LocationTagUpdatedEvent> _tagUpdates;
  Timer? _mapLoadTimer;
  int _loadGeneration = 0;
  bool _initialLoadFailed = false;
  bool _initialTagsLoadFinished = false;
  bool _mapDelayFinished = false;

  @override
  void initState() {
    super.initState();
    _startLoading();
    _tagUpdates = Bus.instance.on<LocationTagUpdatedEvent>().listen((_) {
      unawaited(_refreshTags());
    });
  }

  @override
  void didUpdateWidget(LocationTagsWidgetNew oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.tag != widget.file.tag) {
      _mapLoadTimer?.cancel();
      _loadGeneration++;
      _tags = null;
      _initialLoadFailed = false;
      _initialTagsLoadFinished = false;
      _mapDelayFinished = false;
      _startLoading();
    }
  }

  void _startLoading() {
    unawaited(_refreshTags());
    _mapLoadTimer = Timer(widget.mapLoadDelay, () {
      if (mounted) setState(() => _mapDelayFinished = true);
    });
  }

  Future<void> _refreshTags() async {
    final generation = ++_loadGeneration;
    try {
      final tags = await locationService.enclosingLocationTags(
        widget.file.location!,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _tags = tags;
        _initialLoadFailed = false;
        _initialTagsLoadFinished = true;
      });
    } catch (error, stackTrace) {
      _logger.warning("Unable to load location tags", error, stackTrace);
      if (!mounted || generation != _loadGeneration) return;
      if (_tags == null) {
        setState(() {
          _initialLoadFailed = true;
          _initialTagsLoadFinished = true;
        });
      }
    }
  }

  void _retryInitialLoad() {
    setState(() => _initialLoadFailed = false);
    unawaited(_refreshTags());
  }

  @override
  void dispose() {
    _mapLoadTimer?.cancel();
    _tagUpdates.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FileDetailsAnimatedSize(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppLocalizations.of(context).location,
            style: TextStyles.h2.copyWith(
              color: context.componentColors.textBase,
            ),
          ),
          const SizedBox(height: Spacing.lg),
          if (_initialLoadFailed)
            Row(
              children: [
                Text(
                  AppLocalizations.of(context).somethingWentWrong,
                  style: TextStyles.mini.copyWith(
                    color: context.componentColors.textLight,
                  ),
                ),
                const SizedBox(width: Spacing.md),
                ButtonComponent(
                  label: AppLocalizations.of(context).retry,
                  variant: ButtonComponentVariant.link,
                  size: ButtonComponentSize.small,
                  shouldSurfaceExecutionStates: false,
                  onTap: _retryInitialLoad,
                ),
              ],
            )
          else if (_tags == null)
            const FileDetailsChipRowSkeleton()
          else
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.sm,
              children: _buildTagChips(context, _tags!),
            ),
          _FileDetailsInfoMapNew(
            widget.file,
            key: ValueKey(widget.file.tag),
            mapReady: _initialTagsLoadFinished && _mapDelayFinished,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTagChips(
    BuildContext context,
    List<LocalEntity<LocationTag>> tags,
  ) {
    if (tags.isEmpty) {
      return [
        FilterChipComponent(
          label: AppLocalizations.of(context).addLocation,
          onChanged: (_) =>
              showAddLocationSheet(context, widget.file.location!),
        ),
      ];
    }
    return [
      for (final entity in tags)
        FilterChipComponent(
          label: entity.item.name,
          onChanged: (_) => routeToPage(
            context,
            LocationScreenStateProvider(entity, const LocationScreen()),
          ),
        ),
      IconButtonComponent(
        icon: const HugeIcon(
          icon: HugeIcons.strokeRoundedPlusSign,
          size: IconSizes.small,
        ),
        variant: IconButtonComponentVariant.circular,
        shouldSurfaceExecutionStates: false,
        onTap: () => showAddLocationSheet(context, widget.file.location!),
      ),
    ];
  }
}

class _FileDetailsInfoMapNew extends StatefulWidget {
  const _FileDetailsInfoMapNew(this.file, {required this.mapReady, super.key});

  final EnteFile file;
  final bool mapReady;

  @override
  State<_FileDetailsInfoMapNew> createState() => _FileDetailsInfoMapNewState();
}

class _FileDetailsInfoMapNewState extends State<_FileDetailsInfoMapNew> {
  final _mapController = MapController();
  late bool _hasEnabledMap;
  bool _openingMap = false;

  @override
  void initState() {
    super.initState();
    _hasEnabledMap = mapEnabled;
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.sm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.button),
        child: SizedBox(
          height: 124,
          child: !widget.mapReady
              ? _mapSkeleton(context)
              : _hasEnabledMap
              ? _enabledMap()
              : _disabledMap(context),
        ),
      ),
    );
  }

  Widget _enabledMap() {
    final latitude = widget.file.location!.latitude!;
    final longitude = widget.file.location!.longitude!;
    return Stack(
      children: [
        MapView(
          updateVisibleImages: () {},
          imageMarkers: [
            ImageMarker(
              imageFile: widget.file,
              latitude: latitude,
              longitude: longitude,
            ),
          ],
          controller: _mapController,
          center: LatLng(latitude, longitude),
          minZoom: 12,
          maxZoom: 12,
          initialZoom: 12,
          bottomSheetDraggableAreaHeight: 0,
          showControls: false,
          interactiveFlags: InteractiveFlag.none,
          mapAttributionOptions: MapAttributionOptions(
            permanentHeight: 16,
            popupBorderRadius: BorderRadius.circular(4),
            iconSize: 16,
          ),
          onTap: _openFullMap,
          markerSize: const Size(45, 45),
        ),
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.button),
              border: Border.all(color: context.componentColors.strokeFaint),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }

  Widget _disabledMap(BuildContext context) {
    return Material(
      color: context.componentColors.fillLight,
      child: InkWell(
        onTap: () async {
          try {
            await setMapEnabled(true);
            if (mounted) {
              setState(() => _hasEnabledMap = true);
            }
          } catch (_) {
            if (context.mounted) {
              showShortToast(
                context,
                AppLocalizations.of(context).somethingWentWrong,
              );
            }
          }
        },
        child: Center(
          child: Text(
            AppLocalizations.of(context).enableMaps,
            style: TextStyles.body.copyWith(
              color: context.componentColors.textBase,
            ),
          ),
        ),
      ),
    );
  }

  Widget _mapSkeleton(BuildContext context) => ColoredBox(
    color: context.componentColors.fillLight,
    child: Center(
      child: Container(
        width: 72,
        height: 9,
        decoration: BoxDecoration(
          color: context.componentColors.strokeFaint.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    ),
  );

  void _openFullMap() {
    if (_openingMap) return;
    _openingMap = true;
    final latitude = widget.file.location!.latitude!;
    final longitude = widget.file.location!.longitude!;
    unawaited(
      Navigator.of(context)
          .push(
            MaterialPageRoute(
              builder: (_) => MapScreen(
                filesFutureFn: SearchService.instance.getAllFilesForSearch,
                center: LatLng(latitude, longitude),
                initialZoom: 16,
              ),
            ),
          )
          .whenComplete(() {
            _openingMap = false;
          }),
    );
  }
}
