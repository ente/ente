import "package:flutter/material.dart";
import "package:photos/models/search/hierarchical/face_filter.dart";
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";
import "package:photos/models/search/hierarchical/only_them_filter.dart";

class SearchFilterDataProvider {
  final _appliedFiltersNotifier = _AppliedFiltersNotifier();

  final _recommendedFiltersNotifier = _RecommendedFiltersNotifier();
  final isSearchingNotifier = ValueNotifier(false);
  HierarchicalSearchFilter initialGalleryFilter;

  SearchFilterDataProvider({required this.initialGalleryFilter});

  // Ordered from most to least relevant.
  List<HierarchicalSearchFilter> get recommendations =>
      _recommendedFiltersNotifier.recommendedFilters;
  List<HierarchicalSearchFilter> get appliedFilters =>
      _appliedFiltersNotifier.appliedFilters;

  void clearAndAddRecommendations(List<HierarchicalSearchFilter> filters) {
    _recommendedFiltersNotifier.clearFilters();
    _safelyAddToRecommended(filters);
  }

  void applyFilters(List<HierarchicalSearchFilter> filters) {
    _recommendedFiltersNotifier.removeFilters(filters);

    late final List<HierarchicalSearchFilter> allFiltersToAdd;
    if (!isSearchingNotifier.value) {
      isSearchingNotifier.value = true;
      allFiltersToAdd = [initialGalleryFilter, ...filters];
    } else {
      allFiltersToAdd = filters;
    }

    for (HierarchicalSearchFilter filter in allFiltersToAdd) {
      filter.isApplied = true;
    }
    _appliedFiltersNotifier.addFilters(allFiltersToAdd);

    if (filters.any((e) => e is OnlyThemFilter)) {
      _appliedFiltersNotifier.removeAllFaceFilters();
    }
  }

  void removeAppliedFilters(List<HierarchicalSearchFilter> filters) {
    _appliedFiltersNotifier.removeFilters(filters);
    for (HierarchicalSearchFilter filter in filters) {
      filter.isApplied = false;
    }
    _safelyAddToRecommended(filters);
  }

  void addListener({
    bool toApplied = false,
    bool toRecommended = false,
    required VoidCallback listener,
  }) {
    assert(
      toApplied != false || toRecommended != false,
      "Listener not added to any notifier",
    );
    if (toApplied) {
      _appliedFiltersNotifier.addListener(listener);
    } else if (toRecommended) {
      _recommendedFiltersNotifier.addListener(listener);
    }
  }

  void removeListener({
    bool fromApplied = false,
    bool fromRecommended = false,
    required VoidCallback listener,
  }) {
    assert(
      fromApplied != false || fromRecommended != false,
      "Listener not removed from any notifier",
    );
    if (fromApplied) {
      _appliedFiltersNotifier.removeListener(listener);
    } else if (fromRecommended) {
      _recommendedFiltersNotifier.removeListener(listener);
    }
  }

  void _safelyAddToRecommended(List<HierarchicalSearchFilter> filters) {
    if (_appliedFiltersNotifier.appliedFilters.any(
      (e) => e is OnlyThemFilter,
    )) {
      filters.removeWhere((e) => e is FaceFilter);
    }

    filters.sort((a, b) => b.relevance().compareTo(a.relevance()));

    final List<HierarchicalSearchFilter> filtersToAvoid = [
      ...appliedFilters,
      ...recommendations,
    ];

    if (appliedFilters.isEmpty) {
      filtersToAvoid.add(initialGalleryFilter);
    }

    _recommendedFiltersNotifier.addFilters(
      filters,
      filtersToAvoid: filtersToAvoid,
    );
  }

  void dispose() {
    _appliedFiltersNotifier.dispose();
    _recommendedFiltersNotifier.dispose();
    isSearchingNotifier.dispose();
  }
}

class _AppliedFiltersNotifier extends ChangeNotifier {
  final List<HierarchicalSearchFilter> _appliedFilters = [];

  List<HierarchicalSearchFilter> get appliedFilters => _appliedFilters;

  void addFilters(List<HierarchicalSearchFilter> filters) {
    _appliedFilters.addAll(filters);
    notifyListeners();
  }

  void removeFilters(List<HierarchicalSearchFilter> filters) {
    _appliedFilters.removeWhere((filter) => filters.contains(filter));
    notifyListeners();
  }

  void removeAllFaceFilters() {
    _appliedFilters.removeWhere((element) => element is FaceFilter);
    notifyListeners();
  }
}

class _RecommendedFiltersNotifier extends ChangeNotifier {
  final List<HierarchicalSearchFilter> _recommendedFilters = [];

  List<HierarchicalSearchFilter> get recommendedFilters => _recommendedFilters;

  void addFilters(
    List<HierarchicalSearchFilter> filters, {
    required List<HierarchicalSearchFilter> filtersToAvoid,
  }) {
    for (HierarchicalSearchFilter filter in filters) {
      bool avoidFilter = false;
      for (HierarchicalSearchFilter filterToAvoid in filtersToAvoid) {
        if (filter.isSameFilter(filterToAvoid)) {
          avoidFilter = true;
          break;
        }
      }
      if (avoidFilter) {
        continue;
      }
      _recommendedFilters.add(filter);
    }

    notifyListeners();
  }

  void removeFilters(List<HierarchicalSearchFilter> filters) {
    _recommendedFilters.removeWhere((filter) => filters.contains(filter));
    notifyListeners();
  }

  void clearFilters() {
    _recommendedFilters.clear();
    notifyListeners();
  }
}
