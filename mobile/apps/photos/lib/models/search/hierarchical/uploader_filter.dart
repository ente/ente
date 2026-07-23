import "package:hugeicons/hugeicons.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";

class UploaderFilter extends HierarchicalSearchFilter {
  final String uploaderName;
  final int occurrence;

  UploaderFilter({
    required this.uploaderName,
    required this.occurrence,
    super.filterTypeName = "uploaderFilter",
    super.matchedUploadedIDs,
  });

  @override
  String name() {
    return uploaderName;
  }

  @override
  int relevance() {
    return occurrence;
  }

  @override
  bool isMatch(EnteFile file) {
    return file.uploaderName == uploaderName;
  }

  @override
  bool isSameFilter(HierarchicalSearchFilter other) {
    if (other is UploaderFilter) {
      return other.uploaderName == uploaderName;
    }
    return false;
  }

  @override
  SearchFilterIcon icon() {
    return HugeIcons.strokeRoundedUser;
  }
}
