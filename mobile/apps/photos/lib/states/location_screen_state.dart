import "dart:async";

import "package:flutter/material.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/location_tag_updated_event.dart";
import "package:photos/models/local_entity_data.dart";
import 'package:photos/models/location_tag/location_tag.dart';

class LocationScreenStateProvider extends StatefulWidget {
  final LocalEntity<LocationTag> locationTagEntity;
  final Widget child;
  const LocationScreenStateProvider(
    this.locationTagEntity,
    this.child, {
    super.key,
  });

  @override
  State<LocationScreenStateProvider> createState() =>
      _LocationScreenStateProviderState();
}

class _LocationScreenStateProviderState
    extends State<LocationScreenStateProvider> {
  late LocalEntity<LocationTag> _locationTagEntity;
  late final StreamSubscription _locTagUpdateListener;
  @override
  void initState() {
    _locationTagEntity = widget.locationTagEntity;
    _locTagUpdateListener = Bus.instance.on<LocationTagUpdatedEvent>().listen((
      event,
    ) {
      if (event.type == LocTagEventType.update) {
        setState(() {
          _locationTagEntity = event.updatedLocTagEntities!.first;
        });
      }
    });
    super.initState();
  }

  @override
  dispose() {
    _locTagUpdateListener.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InheritedLocationScreenState(
      _locationTagEntity,
      child: widget.child,
    );
  }
}

class InheritedLocationScreenState extends InheritedWidget {
  final LocalEntity<LocationTag> locationTagEntity;
  const InheritedLocationScreenState(
    this.locationTagEntity, {
    super.key,
    required super.child,
  });

  //This is used to show loading state when memory count is beign computed and to
  //show count after computation.
  static final memoryCountNotifier = ValueNotifier<int?>(null);

  static InheritedLocationScreenState of(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<InheritedLocationScreenState>()!;
  }

  @override
  bool updateShouldNotify(covariant InheritedLocationScreenState oldWidget) {
    return oldWidget.locationTagEntity != locationTagEntity;
  }
}
