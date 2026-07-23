import "package:hugeicons/hugeicons.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/location_tag/location_tag.dart";
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";
import "package:photos/services/location_service.dart";

class LocationFilter extends HierarchicalSearchFilter {
  final LocationTag locationTag;
  final int occurrence;

  LocationFilter({
    required this.locationTag,
    required this.occurrence,
    super.filterTypeName = "locationFilter",
    super.matchedUploadedIDs,
  });

  @override
  String name() {
    return locationTag.name;
  }

  @override
  int relevance() {
    return occurrence;
  }

  @override
  bool isMatch(EnteFile file) {
    if (!file.hasLocation) return false;
    return isFileInsideLocationTag(
      locationTag.centerPoint,
      file.location!,
      locationTag.radius,
    );
  }

  @override
  bool isSameFilter(HierarchicalSearchFilter other) {
    if (other is LocationFilter) {
      return other.locationTag.radius.toString() +
              other.locationTag.centerPoint.toString() +
              other.locationTag.name ==
          locationTag.radius.toString() +
              locationTag.centerPoint.toString() +
              locationTag.name;
    }
    return false;
  }

  @override
  SearchFilterIcon icon() {
    return HugeIcons.strokeRoundedLocation01;
  }
}
