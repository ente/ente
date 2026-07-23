import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/viewer/gallery/state/search_filter_data_provider.dart";
import "package:photos/ui/viewer/hierarchicial_search/chip_widgets/hierarchical_filter_chip.dart";
import "package:photos/utils/hierarchical_search_util.dart";

class FilterOptionsBottomSheet extends StatefulWidget {
  final SearchFilterDataProvider searchFilterDataProvider;
  const FilterOptionsBottomSheet(this.searchFilterDataProvider, {super.key});

  @override
  State<FilterOptionsBottomSheet> createState() =>
      _FilterOptionsBottomSheetState();
}

class _FilterOptionsBottomSheetState extends State<FilterOptionsBottomSheet> {
  static const _maxContentHeightFactor = 0.68;
  static const _topFadeHeight = 16.0;
  static const _peopleAvatarSize = 48.0;

  late final Map<String, List<HierarchicalSearchFilter>> _filtersByType;

  @override
  void initState() {
    super.initState();
    _filtersByType = getFiltersForBottomSheet(widget.searchFilterDataProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filterGroups = _filterGroups(context);

    return BottomSheetComponent(
      title: l10n.filters,
      closeTooltip: l10n.close,
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight:
              MediaQuery.sizeOf(context).height * _maxContentHeightFactor,
        ),
        child: _TopFadingScrollView(
          fadeHeight: _topFadeHeight,
          child: SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final group in filterGroups) ...[
                  _buildFilterGroup(context, group),
                  if (group != filterGroups.last) const SizedBox(height: 24),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterGroup(BuildContext context, _FilterGroup group) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(group.label, style: getEnteTextTheme(context).smallBold),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 12,
          children: [
            for (final filter in group.filters)
              _buildFilterChip(filter, faceAvatarSize: group.faceAvatarSize),
          ],
        ),
      ],
    );
  }

  Widget _buildFilterChip(
    HierarchicalSearchFilter filter, {
    double? faceAvatarSize,
  }) {
    return HierarchicalFilterChip(
      filter: filter,
      apply: () => _applyFilter(filter),
      remove: () => _removeFilter(filter),
      faceAvatarSize: faceAvatarSize,
    );
  }

  void _applyFilter(HierarchicalSearchFilter filter) {
    widget.searchFilterDataProvider.applyFilters([filter]);
    Navigator.of(context).pop();
  }

  void _removeFilter(HierarchicalSearchFilter filter) {
    widget.searchFilterDataProvider.removeAppliedFilters([filter]);
    Navigator.of(context).pop();
  }

  List<_FilterGroup> _filterGroups(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final peopleFilters = _peopleFilters;
    final groups = [
      _FilterGroup(
        l10n.people,
        peopleFilters,
        faceAvatarSize: _peopleAvatarSize,
      ),
      _FilterGroup(l10n.smartSuggestions, [
        ..._filters("magicFilters"),
        ..._filters("topLevelGenericFilter"),
      ]),
      _FilterGroup(l10n.searchResultUploadedBy, _uploadedByFilters),
      _FilterGroup(l10n.camera, _filters("cameraFilters")),
      _FilterGroup(l10n.albums, _filters("albumFilters")),
      _FilterGroup(l10n.locations, _filters("locationFilters")),
      _FilterGroup(l10n.fileTypes, _filters("fileTypeFilters")),
    ];

    return groups.where((group) => group.filters.isNotEmpty).toList();
  }

  List<HierarchicalSearchFilter> get _peopleFilters {
    final faceFilters = _filters("faceFilters");
    final onlyThemFilters = _filters("onlyThemFilter");
    return [
      ...faceFilters.where((filter) => filter.isApplied),
      ...onlyThemFilters.where((filter) => filter.isApplied),
      ...onlyThemFilters.where((filter) => !filter.isApplied),
      ...faceFilters.where((filter) => !filter.isApplied),
    ];
  }

  List<HierarchicalSearchFilter> get _uploadedByFilters {
    return [..._filters("contactsFilters"), ..._filters("uploaderFilters")];
  }

  List<HierarchicalSearchFilter> _filters(String type) {
    return _filtersByType[type] ?? const [];
  }
}

class _TopFadingScrollView extends StatefulWidget {
  const _TopFadingScrollView({required this.fadeHeight, required this.child});

  final double fadeHeight;
  final Widget child;

  @override
  State<_TopFadingScrollView> createState() => _TopFadingScrollViewState();
}

class _TopFadingScrollViewState extends State<_TopFadingScrollView> {
  bool _hasScrolled = false;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) {
        final fadeStop = (widget.fadeHeight / bounds.height).clamp(0.0, 1.0);
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _hasScrolled
              ? const [Colors.transparent, Colors.black, Colors.black]
              : const [Colors.black, Colors.black, Colors.black],
          stops: [0, fadeStop.toDouble(), 1],
        ).createShader(bounds);
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: _updateHasScrolled,
        child: SingleChildScrollView(child: widget.child),
      ),
    );
  }

  bool _updateHasScrolled(ScrollNotification notification) {
    final hasScrolled = notification.metrics.pixels > 0;
    if (hasScrolled != _hasScrolled) {
      setState(() => _hasScrolled = hasScrolled);
    }
    return false;
  }
}

class _FilterGroup {
  final String label;
  final List<HierarchicalSearchFilter> filters;
  final double? faceAvatarSize;

  const _FilterGroup(this.label, this.filters, {this.faceAvatarSize});
}
