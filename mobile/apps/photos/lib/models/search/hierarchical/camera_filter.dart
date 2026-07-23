import "package:hugeicons/hugeicons.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";

class CameraFilter extends HierarchicalSearchFilter {
  final String cameraModel;
  final int occurrence;

  CameraFilter({
    required this.cameraModel,
    required this.occurrence,
    super.filterTypeName = "cameraFilter",
    super.matchedUploadedIDs,
  });

  @override
  String name() {
    return cameraModel;
  }

  @override
  int relevance() {
    return occurrence;
  }

  @override
  bool isMatch(EnteFile file) {
    return file.cameraModel == cameraModel;
  }

  @override
  bool isSameFilter(HierarchicalSearchFilter other) {
    if (other is CameraFilter) {
      return other.cameraModel == cameraModel;
    }
    return false;
  }

  @override
  SearchFilterIcon icon() {
    return HugeIcons.strokeRoundedCamera01;
  }
}
