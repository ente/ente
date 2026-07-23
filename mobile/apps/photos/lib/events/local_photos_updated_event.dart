import 'package:photos/events/files_updated_event.dart';

class LocalPhotosUpdatedEvent extends FilesUpdatedEvent {
  /// True when newly discovered local files include at least one
  /// created within the last 7 days. Used to trigger priority refresh.
  final bool hasRecentNewLocalDiscovery;

  LocalPhotosUpdatedEvent(
    super.updatedFiles, {
    type,
    required source,
    this.hasRecentNewLocalDiscovery = false,
  }) : super(type: type ?? EventType.addedOrUpdated, source: source ?? "");
}
