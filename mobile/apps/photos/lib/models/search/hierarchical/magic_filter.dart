import "package:hugeicons/hugeicons.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";

class MagicFilter extends HierarchicalSearchFilter {
  final String filterName;
  final int occurrence;

  MagicFilter({
    required this.filterName,
    required this.occurrence,
    super.filterTypeName = "magicFilter",
    super.matchedUploadedIDs,
  });

  @override
  SearchFilterIcon icon() {
    return HugeIcons.strokeRoundedSparkles;
  }

  @override
  bool isMatch(EnteFile file) {
    throw UnimplementedError();
  }

  @override
  bool isSameFilter(HierarchicalSearchFilter other) {
    if (other is MagicFilter && other.name() == name()) {
      return true;
    }

    return false;
  }

  @override
  String name() {
    return filterName;
  }

  @override
  int relevance() {
    return occurrence;
  }
}
