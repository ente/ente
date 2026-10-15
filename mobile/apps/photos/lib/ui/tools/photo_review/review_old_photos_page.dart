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

  final _service = PhotoReviewService.instance;
  final _reloadDebouncer = Debouncer(const Duration(seconds: 2));
  late final StreamSubscription<FilesUpdatedEvent> _filesSubscription;
  late final StreamSubscription<PhotoReviewUpdatedEvent> _reviewSubscription;

  ReviewOverview? _overview;
  Object? _error;
  final Set<ReviewMonthKey> _selected = {};
  final Set<int> _expandedYears = {};
  bool _selectionMode = false;
  final _selectionBarKey = GlobalKey();
  double _selectionBarHeight = 0;
  int _loadGeneration = 0;
  bool _covered = false;
  bool _reloadWhenUncovered = false;

  @override
  void initState() {
    super.initState();
    _filesSubscription = Bus.instance.on<FilesUpdatedEvent>().listen(
      (_) => _scheduleReload(debounce: true),
    );
    _reviewSubscription = Bus.instance.on<PhotoReviewUpdatedEvent>().listen(
      (_) => _scheduleReload(debounce: false),
    );
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
    if (_reloadDebouncer.isActive()) {
      _reloadDebouncer.cancelDebounce();
      _reloadWhenUncovered = true;
    }
  }

  @override
  void didPopNext() {
    _covered = false;
    if (_reloadWhenUncovered) {
      _reloadWhenUncovered = false;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    AppNavigationService.instance.routeObserver.unsubscribe(this);
    _filesSubscription.cancel();
    _reviewSubscription.cancel();
    _reloadDebouncer.cancelDebounceTimer();
    super.dispose();
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
    if (_covered) {
      _reloadWhenUncovered = true;
    } else if (debounce) {
      _reloadDebouncer.run(_load);
    } else {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (_covered) {
      _reloadWhenUncovered = true;
      return;
    }
    final generation = ++_loadGeneration;
    try {
      final overview = await _service.loadOverview();
      if (!mounted || generation != _loadGeneration) return;
      final existingKeys = overview.months.map((month) => month.key).toSet();
      setState(() {
        _overview = overview;
        _error = null;
        _selected.retainAll(existingKeys);
        if (_selected.isEmpty) _selectionMode = false;
      });
    } catch (e, s) {
      _logger.severe("Failed to load review overview", e, s);
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  void _openMonth(ReviewMonthKey key) {
    unawaited(routeToPage(context, ReviewMonthPage(monthKey: key)));
  }

  void _toggleMonth(ReviewMonthKey key) {
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      if (!_selected.remove(key)) _selected.add(key);
      _selectionMode = _selected.isNotEmpty;
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
      _selectionMode = _selected.isNotEmpty;
    });
  }

  void _clearSelection() {
    setState(() {
      _selected.clear();
      _selectionMode = false;
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
    final canMarkReviewed = _selectedSummaries.any(
      (month) => !month.isCompleted,
    );
    final canReviewAgain = _selectedSummaries.any((month) => month.hasProgress);
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
            AppBarComponent(
              title: l10n.reviewOldPhotos,
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
                      sliver: SliverList.list(
                        children: [
                          for (var i = 0; i < overview.years.length; i++) ...[
                            if (i > 0) const SizedBox(height: 44),
                            ReviewYearSection(
                              year: overview.years[i],
                              selectedMonths: _selected,
                              expanded: _expandedYears.contains(
                                overview.years[i].year,
                              ),
                              onMonthTap: (month) => _selectionMode
                                  ? _toggleMonth(month.key)
                                  : _openMonth(month.key),
                              onMonthLongPress: (month) =>
                                  _toggleMonth(month.key),
                              onYearToggle: () =>
                                  _toggleYear(overview.years[i]),
                              onExpandedChanged: (expanded) => setState(() {
                                if (expanded) {
                                  _expandedYears.add(overview.years[i].year);
                                } else {
                                  _expandedYears.remove(overview.years[i].year);
                                }
                              }),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
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
                          _selectionMode = false;
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
