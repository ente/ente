import "dart:async";

import "package:collection/collection.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/location_tag_updated_event.dart";
import "package:photos/models/local_entity_data.dart";
import "package:photos/models/location/location.dart";
import "package:photos/models/location_tag/location_tag.dart";
import "package:photos/models/typedefs.dart";

class LocationTagStateProvider extends StatefulWidget {
  final LocalEntity<LocationTag>? locationTagEntity;
  final Location? centerPoint;
  final double? radius;
  final Widget child;
  const LocationTagStateProvider(
    this.child, {
    this.centerPoint,
    this.locationTagEntity,
    // if the locationTagEntity is null, we use the centerPoint and radius
    this.radius,
    super.key,
  });

  @override
  State<LocationTagStateProvider> createState() =>
      _LocationTagStateProviderState();
}

class _LocationTagStateProviderState extends State<LocationTagStateProvider> {
  late double _selectedRadius;

  late Location? _centerPoint;
  late LocalEntity<LocationTag>? _locationTagEntity;
  final Debouncer _selectedRadiusDebouncer = Debouncer(
    const Duration(milliseconds: 300),
  );
  late final StreamSubscription _locTagEntityListener;
  late final List<double> _radiusValues;

  @override
  void initState() {
    _locationTagEntity = widget.locationTagEntity;
    _centerPoint = widget.centerPoint;
    assert(_centerPoint != null || _locationTagEntity != null);
    _centerPoint = _locationTagEntity?.item.centerPoint ?? _centerPoint!;

    ///If the location tag has a custom radius value, we add the custom radius
    ///value to the list of default radius values only for this location tag and
    ///keep it in the state of this widget.
    _radiusValues = _getRadiusValuesOfLocTag(
      _locationTagEntity?.item.radius ?? widget.radius,
    );

    _selectedRadius =
        _locationTagEntity?.item.radius ?? widget.radius ?? defaultRadiusValue;

    _locTagEntityListener = Bus.instance.on<LocationTagUpdatedEvent>().listen((
      event,
    ) {
      _locationTagUpdateListener(event);
    });
    super.initState();
  }

  @override
  void dispose() {
    _locTagEntityListener.cancel();
    super.dispose();
  }

  void _locationTagUpdateListener(LocationTagUpdatedEvent event) {
    if (event.type == LocTagEventType.update) {
      if (event.updatedLocTagEntities!.first.id == _locationTagEntity!.id) {
        setState(() {
          final updatedLocTagEntity = event.updatedLocTagEntities!.first;

          _selectedRadius = updatedLocTagEntity.item.radius;

          _centerPoint = updatedLocTagEntity.item.centerPoint;
          _locationTagEntity = updatedLocTagEntity;
        });
      }
    }
  }

  void _updateSelectedRadius(double radius) {
    _selectedRadiusDebouncer.cancelDebounceTimer();
    _selectedRadiusDebouncer.run(() async {
      if (mounted) {
        setState(() {
          _selectedRadius = radius;
        });
      }
    });
  }

  void _updateCenterPoint(Location centerPoint) {
    if (mounted) {
      setState(() {
        _centerPoint = centerPoint;
      });
    }
  }

  void _updateRadiusValues(List<double> radiusValues) {
    if (mounted) {
      setState(() {
        for (double radiusValue in radiusValues) {
          if (!_radiusValues.contains(radiusValue)) {
            _radiusValues.add(radiusValue);
          }
        }
        _radiusValues.sort();
      });
    }
  }

  ///Returns the list of radius values for the location tag entity. If radius of
  ///the location tag is not present in the default list, it returns the list
  ///with the custom radius value.
  List<double> _getRadiusValuesOfLocTag(double? radiusOfLocTag) {
    final radiusValues = <double>[...defaultRadiusValues];
    if (radiusOfLocTag != null &&
        !defaultRadiusValues.contains(radiusOfLocTag)) {
      radiusValues.add(radiusOfLocTag);
      radiusValues.sort();
    }
    return radiusValues;
  }

  @override
  Widget build(BuildContext context) {
    return InheritedLocationTagData(
      _selectedRadius,
      _centerPoint!,
      _updateSelectedRadius,
      _locationTagEntity,
      _updateCenterPoint,
      _updateRadiusValues,
      _radiusValues,
      child: widget.child,
    );
  }
}

///This InheritedWidget's state is used in add & edit location sheets
class InheritedLocationTagData extends InheritedWidget {
  final double selectedRadius;
  final Location centerPoint;
  //locationTag is null when we are creating a new location tag in add location sheet
  final LocalEntity<LocationTag>? locationTagEntity;
  final VoidCallbackParamDouble updateSelectedRadius;
  final VoidCallbackParamLocation updateCenterPoint;
  final VoidCallbackParamListDouble updateRadiusValues;
  final List<double> radiusValues;
  const InheritedLocationTagData(
    this.selectedRadius,
    this.centerPoint,
    this.updateSelectedRadius,
    this.locationTagEntity,
    this.updateCenterPoint,
    this.updateRadiusValues,
    this.radiusValues, {
    required super.child,
    super.key,
  });

  static InheritedLocationTagData of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<InheritedLocationTagData>()!;
  }

  @override
  bool updateShouldNotify(InheritedLocationTagData oldWidget) {
    return oldWidget.selectedRadius != selectedRadius ||
        !oldWidget.radiusValues.equals(radiusValues) ||
        oldWidget.centerPoint != centerPoint ||
        oldWidget.locationTagEntity != locationTagEntity;
  }
}
