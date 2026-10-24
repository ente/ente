import "package:photos/events/event.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/people_changed_event.dart";
import "package:photos/services/machine_learning/face_ml/feedback/cluster_feedback.dart";

/// Requery suggestions and their prepared previews together after membership
/// changes, rather than editing only the displayed file list.
bool reviewSuggestionsAffectedBy(
  Event event,
  Iterable<ClusterSuggestion> suggestions, {
  bool previewOpen = false,
  bool suggestionsLoading = false,
  String? personID,
}) {
  if (event is PeopleChangedEvent &&
      event.type == PeopleEventType.reviewedSuggestion) {
    return personID == null || event.person?.remoteID == personID;
  }
  // Splitting a group emits an unscoped change. Cards mounted beneath the
  // preview must also refresh, even though their own preview is not open.
  if (event is PeopleChangedEvent &&
      (previewOpen ||
          (event.type == PeopleEventType.defaultType &&
              event.source.isEmpty &&
              event.person == null &&
              event.persons == null))) {
    return true;
  }
  if (event is FilesUpdatedEvent) {
    if (event.source == "moveFrom" ||
        (event.type != EventType.deletedFromEverywhere &&
            event.type != EventType.deletedFromRemote &&
            event.type != EventType.hide)) {
      return false;
    }
    final ids = event.updatedFiles
        .map((file) => file.uploadedFileID)
        .nonNulls
        .toSet();
    // Before a query returns, its captured membership is not available to
    // determine whether this event affects it. Invalidate that query as well.
    if (suggestionsLoading) return true;
    return suggestions.any(
      (suggestion) => suggestion.filesInCluster.any(
        (file) => ids.contains(file.uploadedFileID),
      ),
    );
  }
  if (event is PeopleChangedEvent &&
      (event.type == PeopleEventType.removedFilesFromCluster ||
          event.type == PeopleEventType.removedFaceFromCluster)) {
    return suggestionsLoading ||
        suggestions.any(
          (suggestion) => suggestion.clusterIDToMerge == event.source,
        );
  }
  return false;
}
