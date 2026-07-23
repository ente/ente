import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";
import "package:photos/ui/viewer/gallery/state/inherited_search_filter_data.dart";
import "package:photos/ui/viewer/gallery/state/search_filter_data_provider.dart";
import "package:photos/ui/viewer/hierarchicial_search/chip_widgets/hierarchical_filter_chip.dart";
import "package:photos/ui/viewer/hierarchicial_search/filter_options_bottom_sheet.dart";
import "package:photos/utils/hierarchical_search_util.dart";

class AppBarFilterChips extends StatefulWidget {
  const AppBarFilterChips({super.key});

  static const bottomPadding = 8.0;

  static double chipHeight(BuildContext context) {
    return FilterChipComponent.heightForTextScale(context);
  }

  static double preferredHeight(BuildContext context) {
    return chipHeight(context) + bottomPadding;
  }

  static double appBarHeight(BuildContext context) {
    return kToolbarHeight + preferredHeight(context);
  }

  @override
  State<AppBarFilterChips> createState() => _AppBarFilterChipsState();
}

class _AppBarFilterChipsState extends State<AppBarFilterChips> {
  final _filterChipKeys = <HierarchicalSearchFilter, GlobalKey>{};
  SearchFilterDataProvider? _searchFilterDataProvider;
  HierarchicalSearchFilter? _filterToRevealAfterApply;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final inheritedSearchFilterData = InheritedSearchFilterData.of(context);
    assert(
      inheritedSearchFilterData.isHierarchicalSearchable,
      "Do not use this widget if gallery is not hierarchical searchable",
    );
    final searchFilterDataProvider =
        inheritedSearchFilterData.searchFilterDataProvider!;
    if (_searchFilterDataProvider == searchFilterDataProvider) {
      return;
    }
    _searchFilterDataProvider?.removeListener(
      fromApplied: true,
      listener: _onFiltersUpdate,
    );
    _searchFilterDataProvider?.removeListener(
      fromRecommended: true,
      listener: _onFiltersUpdate,
    );
    _searchFilterDataProvider = searchFilterDataProvider;
    searchFilterDataProvider.addListener(
      toApplied: true,
      listener: _onFiltersUpdate,
    );
    searchFilterDataProvider.addListener(
      toRecommended: true,
      listener: _onFiltersUpdate,
    );
  }

  @override
  void dispose() {
    _searchFilterDataProvider?.removeListener(
      fromApplied: true,
      listener: _onFiltersUpdate,
    );
    _searchFilterDataProvider?.removeListener(
      fromRecommended: true,
      listener: _onFiltersUpdate,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final searchFilterDataProvider = _searchFilterDataProvider!;
    final appliedFilters = searchFilterDataProvider.appliedFilters;
    final recommendations = getRecommendedFiltersForAppBar(
      searchFilterDataProvider,
    );
    if (appliedFilters.isEmpty && recommendations.isEmpty) {
      return const SizedBox.shrink();
    }

    final chipHeight = AppBarFilterChips.chipHeight(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppBarFilterChips.bottomPadding),
      child: SizedBox(
        width: double.infinity,
        height: chipHeight,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              _buildAllFiltersButton(
                context,
                searchFilterDataProvider,
                chipHeight,
              ),
              for (final filter in appliedFilters)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _buildFilterChip(filter),
                ),
              for (final filter in recommendations)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _buildFilterChip(filter),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAllFiltersButton(
    BuildContext context,
    SearchFilterDataProvider searchFilterDataProvider,
    double chipHeight,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        height: chipHeight,
        child: Center(
          child: IconButtonComponent(
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedMenu08,
              size: IconSizes.small,
            ),
            variant: IconButtonComponentVariant.primary,
            shouldSurfaceExecutionStates: false,
            tooltip: AppLocalizations.of(context).filter,
            onTap: () => showBottomSheetComponent(
              context: context,
              builder: (_) =>
                  FilterOptionsBottomSheet(searchFilterDataProvider),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(HierarchicalSearchFilter filter) {
    final chipKey = _keyForFilter(filter);
    return KeyedSubtree(
      key: chipKey,
      child: HierarchicalFilterChip(
        filter: filter,
        apply: () => _applyFilter(filter),
        remove: () => _removeFilter(filter),
      ),
    );
  }

  GlobalKey _keyForFilter(HierarchicalSearchFilter filter) {
    return _filterChipKeys[filter] ??= GlobalKey();
  }

  void _applyFilter(HierarchicalSearchFilter filter) {
    _filterToRevealAfterApply = filter;
    _searchFilterDataProvider!.applyFilters([filter]);
  }

  void _removeFilter(HierarchicalSearchFilter filter) {
    _searchFilterDataProvider!.removeAppliedFilters([filter]);
  }

  void _onFiltersUpdate() {
    setState(() {});
    _revealPendingAppliedFilter();
  }

  void _revealPendingAppliedFilter() {
    final filter = _filterToRevealAfterApply;
    if (filter == null) {
      return;
    }
    if (!_searchFilterDataProvider!.appliedFilters.contains(filter)) {
      return;
    }

    _filterToRevealAfterApply = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final chipContext = _filterChipKeys[filter]?.currentContext;
      if (chipContext == null) {
        return;
      }
      Scrollable.ensureVisible(
        chipContext,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
    });
  }
}
