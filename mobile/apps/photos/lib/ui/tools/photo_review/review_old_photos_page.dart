import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/events/photo_review_updated_event.dart";
import "package:photos/models/photo_review/photo_review_models.dart";
import "package:photos/services/app_navigation_service.dart";
import "package:photos/services/photo_review/photo_review_service.dart";
import "package:photos/ui/tools/photo_review/review_month_page.dart";
import "package:photos/ui/tools/photo_review/widgets/review_banner.dart";
import "package:photos/ui/tools/photo_review/widgets/review_selection_bar.dart";
import "package:photos/ui/tools/photo_review/widgets/review_year_section.dart";
import "package:photos/ui/viewer/gallery/scrollbar/scroll_bar_with_use_notifier.dart";
import "package:photos/utils/dialog_util.dart";

class ReviewOldPhotosPage extends StatefulWidget {
  const ReviewOldPhotosPage({super.key});

  @override
  State<ReviewOldPhotosPage> createState() => _ReviewOldPhotosPageState();
}

class _ReviewOldPhotosPageState extends State<ReviewOldPhotosPage>
    with RouteAware {
  static final _logger = Logger("ReviewOldPhotosPage");
  static const _horizontalPadding = Spacing.xl;
  static const _yearSpacing = 44.0;

  final _service = PhotoReviewService.instance;
  final _reloadDebouncer = Debouncer(const Duration(seconds: 2));
  late final StreamSubscription<FilesUpdatedEvent> _filesSubscription;
  late final StreamSubscription<PhotoReviewUpdatedEvent> _reviewSubscription;

  ReviewOverview? _overview;
  Object? _error;
  final Set<ReviewMonthKey> _selected = {};
  final Set<int> _expandedYears = {};
  final Set<ReviewMonthKey> _dirtyMonths = {};
  final Map<ReviewMonthKey, Future<void>> _pendingMonthWrites = {};
  final _selectionBarKey = GlobalKey();
  final _scrollController = ScrollController();
  final _showScrollThumb = ValueNotifier(false);
  final _scrollThumbInUse = ValueNotifier(false);
  double _selectionBarHeight = 0;
  int _loadGeneration = 0;
  bool _loading = false;
  bool _fullReloadRequired = true;
  bool _covered = false;

  bool get _selectionMode => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _filesSubscription = Bus.instance.on<FilesUpdatedEvent>().listen((_) {
      _fullReloadRequired = true;
      _loadGeneration++;
      _scheduleReload(debounce: true);
    });
    _reviewSubscription = Bus.instance.on<PhotoReviewUpdatedEvent>().listen((
      event,
    ) {
      _dirtyMonths.addAll(event.monthKeys);
      if (event.monthKeys.length > 1) _fullReloadRequired = true;
      _loadGeneration++;
      _scheduleReload(debounce: false);
    });
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      AppNavigationService.instance.routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    _covered = true;
    _reloadDebouncer.cancelDebounce();
  }

  @override
  void didPopNext() {
    _covered = false;
    unawaited(_load());
  }

  @override
  void dispose() {
    AppNavigationService.instance.routeObserver.unsubscribe(this);
    _filesSubscription.cancel();
    _reviewSubscription.cancel();
    _reloadDebouncer.cancelDebounceTimer();
    _scrollController.dispose();
    _showScrollThumb.dispose();
    _scrollThumbInUse.dispose();
    super.dispose();
  }

  Widget _withScrollbar(
    Widget Function(BuildContext context, double yearWidth) buildChild,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = MediaQuery.paddingOf(context);
        final header = SliverAppBarComponent.resolveGeometry(context);
        final collapseExtent = header.maxExtent - header.minExtent;
        final child = buildChild(
          context,
          constraints.maxWidth - padding.horizontal - _horizontalPadding * 2,
        );
        return NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            final metrics = notification.metrics;
            if (notification.depth == 0 && metrics.axis == Axis.vertical) {
              _showScrollThumb.value =
                  metrics.viewportDimension > 0 &&
                  metrics.maxScrollExtent - metrics.minScrollExtent >
                      collapseExtent + 1;
            }
            return false;
          },
          child: ValueListenableBuilder<bool>(
            valueListenable: _showScrollThumb,
            child: child,
            builder: (context, showThumb, child) => ScrollbarWithUseNotifer(
              controller: _scrollController,
              inUseNotifier: _scrollThumbInUse,
              interactive: showThumb,
              showThumb: showThumb,
              thumbVisibility: showThumb,
              minScrollbarLength: 36,
              thickness: 8,
              radius: const Radius.circular(4),
              scrollbarPadding: EdgeInsets.only(
                top: header.minExtent,
                bottom: _selectionMode ? _selectionBarHeight : padding.bottom,
                right: 3,
              ),
              child: child!,
            ),
          ),
        );
      },
    );
  }

  Widget _buildYearList(
    BuildContext context,
    ReviewOverview overview,
    double width,
  ) {
    final extents = <double>[];
    for (final year in overview.years) {
      if (extents.isNotEmpty) extents.add(_yearSpacing);
      extents.add(
        ReviewYearSection.heightFor(
          context,
          year: year,
          expanded: _expandedYears.contains(year.year),
          width: width,
        ),
      );
    }
    return SliverList(
      delegate: _ReviewYearListDelegate(
        (context, index) {
          if (index.isOdd) return const SizedBox(height: _yearSpacing);
          final year = overview.years[index ~/ 2];
          return ReviewYearSection(
            key: ValueKey(year.year),
            year: year,
            selectedMonths: _selected,
            expanded: _expandedYears.contains(year.year),
            onMonthTap: (month) => _selectionMode
                ? _toggleMonth(month.key)
                : _openMonth(month.key),
            onMonthLongPress: (month) => _toggleMonth(month.key),
            onYearToggle: () => _toggleYear(year),
            onExpandedChanged: (expanded) => setState(() {
              if (expanded) {
                _expandedYears.add(year.year);
              } else {
                _expandedYears.remove(year.year);
              }
            }),
          );
        },
        extents: extents,
        findChildIndexCallback: (key) {
          if (key is! ValueKey<int>) return null;
          final index = overview.years.indexWhere(
            (year) => year.year == key.value,
          );
          return index < 0 ? null : index * 2;
        },
      ),
    );
  }

  void _measureSelectionBar(Duration _) {
    final box =
        _selectionBarKey.currentContext?.findRenderObject() as RenderBox?;
    final height = box?.size.height ?? 0;
    if (mounted && height != _selectionBarHeight) {
      setState(() => _selectionBarHeight = height);
    }
  }

  void _scheduleReload({required bool debounce}) {
    if (_covered) return;
    if (debounce) {
      _reloadDebouncer.run(_load);
    } else {
      _reloadDebouncer.cancelDebounce();
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (_loading || _covered) return;
    _loading = true;
    try {
      while (mounted &&
          !_covered &&
          !_reloadDebouncer.isActive() &&
          (_fullReloadRequired || _dirtyMonths.isNotEmpty)) {
        final generation = _loadGeneration;
        try {
          await Future.wait(_pendingMonthWrites.values.toList());
          if (!mounted || _covered) return;
          if (generation != _loadGeneration) continue;
          final ReviewOverview overview;
          if (_fullReloadRequired || _overview == null) {
            overview = await _service.loadOverview();
          } else {
            final updates = <ReviewMonthKey, ReviewMonthSummary?>{};
            for (final key in _dirtyMonths.toList()) {
              updates[key] = await _service.loadMonthSummary(key);
              if (!mounted || _covered || generation != _loadGeneration) {
                break;
              }
            }
            if (!mounted || _covered) return;
            if (generation != _loadGeneration) continue;
            overview = _mergeMonths(updates);
          }
          if (!mounted || _covered) return;
          if (generation != _loadGeneration) continue;
          _fullReloadRequired = false;
          _dirtyMonths.clear();
          _pendingMonthWrites.clear();
          _applyOverview(overview);
        } catch (e, s) {
          _logger.severe("Failed to load review overview", e, s);
          if (!mounted) return;
          if (generation != _loadGeneration) continue;
          setState(() => _error = e);
          return;
        }
      }
    } finally {
      _loading = false;
    }
  }

  ReviewOverview _mergeMonths(
    Map<ReviewMonthKey, ReviewMonthSummary?> updates,
  ) => PhotoReviewService.buildOverviewFromMonths([
    for (final month in _overview!.months)
      if (!updates.containsKey(month.key)) month,
    for (final month in updates.values) ?month,
  ]);

  void _applyOverview(ReviewOverview overview) {
    final existingKeys = overview.months.map((month) => month.key).toSet();
    setState(() {
      _overview = overview;
      _error = null;
      _selected.retainAll(existingKeys);
    });
  }

  void _onMonthChanged(
    ReviewMonthKey key,
    ReviewMonthSummary? summary,
    Future<void> pendingWrites,
  ) {
    if (!mounted) return;
    _dirtyMonths.add(key);
    _pendingMonthWrites[key] = pendingWrites;
    _loadGeneration++;
    if (summary != null && _overview != null) {
      _applyOverview(_mergeMonths({key: summary}));
    }
    _scheduleReload(debounce: false);
  }

  Future<void> _writesForMonth(ReviewMonthKey key) =>
      _pendingMonthWrites[key] ?? Future.value();

  Future<void> _waitForMonthWrites(List<ReviewMonthKey> keys) async {
    while (mounted) {
      final writes = [for (final key in keys) _pendingMonthWrites[key]];
      await Future.wait([for (final write in writes) ?write]);
      var settled = true;
      for (var i = 0; i < keys.length; i++) {
        if (!identical(writes[i], _pendingMonthWrites[keys[i]])) {
          settled = false;
          break;
        }
      }
      if (settled) return;
    }
  }

  void _openMonth(ReviewMonthKey key) {
    unawaited(
      routeToPage(
        context,
        ReviewMonthPage(
          monthKey: key,
          onReviewChanged: _onMonthChanged,
          pendingWritesForMonth: _writesForMonth,
        ),
      ),
    );
  }

  void _toggleMonth(ReviewMonthKey key) {
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      if (!_selected.remove(key)) _selected.add(key);
    });
  }

  void _toggleYear(ReviewYearSummary year) {
    unawaited(HapticFeedback.selectionClick());
    final keys = year.months.map((month) => month.key);
    final allSelected = keys.every(_selected.contains);
    setState(() {
      if (allSelected) {
        _selected.removeAll(keys);
      } else {
        _selected.addAll(keys);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selected.clear();
    });
  }

  Iterable<ReviewMonthSummary> get _selectedSummaries =>
      _overview?.months.where((month) => _selected.contains(month.key)) ??
      const [];

  Future<void> _markAsReviewed() async {
    final keys = _selectedSummaries
        .where((month) => !month.isCompleted)
        .map((month) => month.key)
        .toList();
    unawaited(HapticFeedback.mediumImpact());
    try {
      await _waitForMonthWrites(keys);
      if (!mounted) return;
      await _service.markMonthsReviewed(keys);
    } catch (e, s) {
      _logger.severe("Failed to mark months as reviewed", e, s);
      if (mounted) await showGenericErrorDialog(context: context, error: e);
      return;
    }
    if (mounted) _clearSelection();
  }

  Future<void> _reviewAgain() async {
    final keys = _selectedSummaries
        .where((month) => month.hasProgress)
        .map((month) => month.key)
        .toList();
    unawaited(HapticFeedback.mediumImpact());
    try {
      await _waitForMonthWrites(keys);
      if (!mounted) return;
      await _service.resetMonths(keys);
    } catch (e, s) {
      _logger.severe("Failed to reset months", e, s);
      if (mounted) await showGenericErrorDialog(context: context, error: e);
      return;
    }
    if (mounted) _clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback(_measureSelectionBar);
    final colors = context.componentColors;
    final l10n = context.strings;
    final overview = _overview;
    final canMarkReviewed =
        _selectionMode && _selectedSummaries.any((month) => !month.isCompleted);
    final canReviewAgain =
        _selectionMode && _selectedSummaries.any((month) => month.hasProgress);
    final allSelected =
        overview != null &&
        overview.months.isNotEmpty &&
        overview.months.every((month) => _selected.contains(month.key));

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: Scaffold(
        backgroundColor: colors.backgroundBase,
        body: Stack(
          children: [
            _withScrollbar(
              (context, yearWidth) => AppBarComponent(
                title: l10n.reviewOldPhotos,
                controller: _scrollController,
                slivers: [
                  if (overview == null)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: _error == null
                            ? const LoadingComponent()
                            : Padding(
                                padding: const EdgeInsets.all(Spacing.xxl),
                                child: Text(
                                  l10n.somethingWentWrong,
                                  textAlign: TextAlign.center,
                                  style: TextStyles.body.copyWith(
                                    color: colors.textLight,
                                  ),
                                ),
                              ),
                      ),
                    )
                  else if (overview.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: _EmptyReviewState(),
                    )
                  else ...[
                    if (overview.bannerMonths.isNotEmpty)
                      SliverPadding(
                        padding: const EdgeInsets.only(top: Spacing.xxl),
                        sliver: SliverToBoxAdapter(
                          child: ReviewBannerCarousel(
                            months: overview.bannerMonths,
                            horizontalPadding: _horizontalPadding,
                            onTap: (month) => _openMonth(month.key),
                          ),
                        ),
                      ),
                    SliverSafeArea(
                      top: false,
                      sliver: SliverPadding(
                        padding: EdgeInsets.fromLTRB(
                          _horizontalPadding,
                          Spacing.xxl,
                          _horizontalPadding,
                          _selectionMode
                              ? _selectionBarHeight + Spacing.xxl
                              : Spacing.xxl,
                        ),
                        sliver: _buildYearList(context, overview, yearWidth),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: AnimatedSlide(
                offset: _selectionMode ? Offset.zero : const Offset(0, 1),
                duration: Motion.slow,
                curve: Curves.easeOutCubic,
                child: IgnorePointer(
                  ignoring: !_selectionMode,
                  child: ReviewSelectionBar(
                    key: _selectionBarKey,
                    selectedCount: _selected.length,
                    allSelected: allSelected,
                    onSelectAll: () {
                      unawaited(HapticFeedback.selectionClick());
                      setState(() {
                        if (allSelected) {
                          _selected.clear();
                        } else {
                          _selected.addAll(
                            overview?.months.map((month) => month.key) ??
                                const [],
                          );
                        }
                      });
                    },
                    onClear: _clearSelection,
                    onMarkAsReviewed: canMarkReviewed ? _markAsReviewed : null,
                    onReviewAgain: canReviewAgain ? _reviewAgain : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewYearListDelegate extends SliverChildBuilderDelegate {
  _ReviewYearListDelegate(
    super.builder, {
    required List<double> extents,
    required super.findChildIndexCallback,
  }) : _remainingExtents = _suffixExtents(extents),
       super(
         childCount: extents.length,
         semanticIndexCallback: (_, index) => index.isEven ? index ~/ 2 : null,
       );

  final List<double> _remainingExtents;

  static List<double> _suffixExtents(List<double> extents) {
    final remaining = List<double>.filled(extents.length + 1, 0);
    for (var index = extents.length - 1; index >= 0; index--) {
      remaining[index] = remaining[index + 1] + extents[index];
    }
    return remaining;
  }

  @override
  double estimateMaxScrollOffset(
    int firstIndex,
    int lastIndex,
    double leadingScrollOffset,
    double trailingScrollOffset,
  ) => trailingScrollOffset + _remainingExtents[lastIndex + 1];
}

class _EmptyReviewState extends StatelessWidget {
  const _EmptyReviewState();

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final l10n = context.strings;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              "assets/photo_review/all_cleaned_up.svg",
              width: 335,
              height: 133.41,
            ),
            const SizedBox(height: Spacing.xxl),
            Text(
              l10n.nothingToReviewYet,
              textAlign: TextAlign.center,
              style: TextStyles.display2.copyWith(color: colors.textBase),
            ),
            const SizedBox(height: Spacing.md),
            Text(
              l10n.nothingToReviewYetDesc,
              textAlign: TextAlign.center,
              style: TextStyles.body.copyWith(color: colors.textLight),
            ),
          ],
        ),
      ),
    );
  }
}
