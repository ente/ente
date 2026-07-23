import "package:flutter/material.dart";
import "package:photos/service_locator.dart" show isLocalGalleryMode;
import "package:photos/ui/viewer/gallery/state/search_filter_data_provider.dart";

class InheritedSearchFilterDataWrapper extends StatefulWidget {
  const InheritedSearchFilterDataWrapper({
    super.key,
    required this.child,
    required this.searchFilterDataProvider,
  });

  final Widget child;
  final SearchFilterDataProvider? searchFilterDataProvider;

  @override
  State<InheritedSearchFilterDataWrapper> createState() =>
      _InheritedSearchFilterDataWrapperState();
}

class _InheritedSearchFilterDataWrapperState
    extends State<InheritedSearchFilterDataWrapper> {
  @override
  void dispose() {
    widget.searchFilterDataProvider?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InheritedSearchFilterData(
      searchFilterDataProvider: widget.searchFilterDataProvider,
      child: widget.child,
    );
  }
}

/// Use [InheritedSearchFilterDataWrapper] instead if using
/// [InheritedSearchFilterData] as a parent widget
class InheritedSearchFilterData extends InheritedWidget {
  const InheritedSearchFilterData({
    super.key,
    required this.searchFilterDataProvider,
    required super.child,
  });

  /// Pass null if gallery doesn't need hierarchical search
  final SearchFilterDataProvider? searchFilterDataProvider;

  bool get isHierarchicalSearchable =>
      searchFilterDataProvider != null && !isLocalGalleryMode;

  static InheritedSearchFilterData? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<InheritedSearchFilterData>();
  }

  static InheritedSearchFilterData of(BuildContext context) {
    final InheritedSearchFilterData? result = maybeOf(context);
    assert(result != null, 'No InheritedSearchFilterData found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(InheritedSearchFilterData oldWidget) =>
      searchFilterDataProvider != oldWidget.searchFilterDataProvider;
}
