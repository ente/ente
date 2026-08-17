import "package:photos/models/file/file.dart";

int kMostRelevantFilter = 10000;
int kLeastRelevantFilter = -1;

typedef SearchFilterIcon = List<List<dynamic>>;

enum FilterTypeNames {
  albumFilter,
  contactsFilter,
  faceFilter,
  fileTypeFilter,
  locationFilter,
  magicFilter,
  topLevelGenericFilter,
  uploaderFilter,
  onlyThemFilter,
  cameraFilter,
}

abstract class HierarchicalSearchFilter {
  final String filterTypeName;
  // Match every database file so removing another filter can restore results.
  final Set<int> matchedUploadedIDs;
  bool isApplied = false;

  HierarchicalSearchFilter({required this.filterTypeName, matchedUploadedIDs})
    : matchedUploadedIDs = matchedUploadedIDs ?? {},
      assert(
        FilterTypeNames.values
            .map((e) => e.toString().split(".").last)
            .contains(filterTypeName),
        "filterTypeName = $filterTypeName is not a valid filter type in FilterTypeNames enum. Please add it to the enum if it's missing or else, cross check spelling ",
      );

  String name();
  SearchFilterIcon? icon();

  int relevance();
  bool isMatch(EnteFile file);
  bool isSameFilter(HierarchicalSearchFilter other);
}
