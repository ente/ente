import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";
import "package:photos/ui/viewer/gallery/state/search_filter_data_provider.dart";
import "package:photos/utils/hierarchical_search_util.dart";

void main() {
  testWidgets("curateFilters skips when localizations are unavailable", (
    tester,
  ) async {
    late final BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (builderContext) {
          context = builderContext;
          return const SizedBox.shrink();
        },
      ),
    );

    final searchFilterDataProvider = SearchFilterDataProvider(
      initialGalleryFilter: _TestFilter(),
    );

    await curateFilters(searchFilterDataProvider, const [], context);

    expect(searchFilterDataProvider.recommendations, isEmpty);
    searchFilterDataProvider.dispose();
  });
}

class _TestFilter extends HierarchicalSearchFilter {
  _TestFilter()
    : super(
        filterTypeName: "topLevelGenericFilter",
        matchedUploadedIDs: <int>{},
      );

  @override
  SearchFilterIcon? icon() => null;

  @override
  bool isMatch(EnteFile file) => false;

  @override
  bool isSameFilter(HierarchicalSearchFilter other) => other.name() == name();

  @override
  String name() => "test";

  @override
  int relevance() => kLeastRelevantFilter;
}
