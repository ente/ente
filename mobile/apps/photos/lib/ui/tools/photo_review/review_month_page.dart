import "dart:async";
import "dart:io";

import "package:collection/collection.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_components/hugeicons.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:intl/intl.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/photo_review/photo_review_models.dart";
import "package:photos/models/selected_files.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/favorites_service.dart";
import "package:photos/services/photo_review/photo_review_service.dart";
import "package:photos/ui/common/touch_cross_detector.dart";
import "package:photos/ui/components/bottom_action_bar/selection_action_sheet.dart";
import "package:photos/ui/tools/photo_review/widgets/review_grid_tile.dart";
import "package:photos/ui/tools/photo_review/widgets/review_selection_bar.dart";
import "package:photos/ui/tools/photo_review/widgets/review_swipe_stack.dart";
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/ui/viewer/gallery/component/swipe_selectable_file_widget.dart";
import "package:photos/ui/viewer/gallery/state/gallery_boundaries_provider.dart";
import "package:photos/ui/viewer/gallery/swipe_selection_wrapper.dart";
import "package:photos/ui/viewer/gallery/swipe_to_select_helper.dart";
import "package:photos/utils/delete_file_util.dart";
import "package:photos/utils/dialog_util.dart";

enum _ReviewMonthView { grid, swipe, queue, done }

class ReviewMonthPage extends StatefulWidget {
  const ReviewMonthPage({
    required this.monthKey,
    this.onReviewChanged,
    this.pendingWritesForMonth,
    super.key,
  });

  final ReviewMonthKey monthKey;
  final void Function(ReviewMonthKey, ReviewMonthSummary?, Future<void>)?
  onReviewChanged;
  final Future<void> Function(ReviewMonthKey)? pendingWritesForMonth;

  @override
  State<ReviewMonthPage> createState() => _ReviewMonthPageState();
}

class _ReviewMonthPageState extends State<ReviewMonthPage> {
  static final _logger = Logger("ReviewMonthPage");
  static const _tagPrefix = "photo_review_";
  static const _actionButtonSize = 60.0;
  static const _undoButtonSize = 46.0;
  static const _actionButtonSpacing = 40.0;
  static const _bottomActionInset = 25.0;
  static const _queueTileExtent = 120.0;
  static const _gridTileExtent = 100.0;
  static const _gridSpacing = 2.0;

  final _service = PhotoReviewService.instance;
  final _stackController = ReviewSwipeStackController();
  final _reloadDebouncer = Debouncer(
    const Duration(milliseconds: 500),
    executionInterval: const Duration(seconds: 2),
    leading: true,
  );
  late final StreamSubscription<FilesUpdatedEvent> _filesSubscription;

  List<EnteFile> _files = [];
  final Map<String, ReviewDecision> _decisions = {};
  final List<EnteFile> _undecided = [];
  final List<EnteFile> _deck = [];
  EnteFile? _deckAnchor;
  final _selection = SelectedFiles();
  late final _swipeHelper = SwipeToSelectHelper(
    allFiles: _undecided,
    selectedFiles: _selection,
  );
  final _swipeActiveNotifier = ValueNotifier<bool>(false);
  bool? _reloadAfterSwipe;
  int? _gridPointer;
  final _gridScrollController = ScrollController();
  final _boundariesKey = GlobalKey<GalleryBoundariesProviderState>();
  final _selectionBarKey = GlobalKey();
  double _selectionBarHeight = 0;
  final List<(EnteFile, ReviewSwipeDirection)> _history = [];
  ReviewMonthRecord? _record;
  late Future<void> _lastWrite;
  int _lastReviewedAt = 0;
  int _queuedCount = 0;
  int _loadGeneration = 0;
  int _filesRevision = 0;
  int _loadedFilesRevision = -1;
  bool _loaded = false;
  bool _deleting = false;
  bool _leaving = false;
  bool _reviewChanged = false;
  bool _reportingWriteFailure = false;
  _ReviewMonthView _view = _ReviewMonthView.grid;
  _ReviewMonthView _queueOrigin = _ReviewMonthView.grid;

  @override
  void initState() {
    super.initState();
    _lastWrite =
        widget.pendingWritesForMonth?.call(widget.monthKey) ?? Future.value();
    _filesSubscription = Bus.instance.on<FilesUpdatedEvent>().listen(
      _onFilesUpdated,
    );
    _selection.addListener(_onSelectionChanged);
    _swipeActiveNotifier.addListener(_onSwipeActiveChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _filesSubscription.cancel();
    _reloadDebouncer.cancelDebounceTimer();
    _swipeHelper.dispose();
    _selection
      ..removeListener(_onSelectionChanged)
      ..dispose();
    _swipeActiveNotifier
      ..removeListener(_onSwipeActiveChanged)
      ..dispose();
    _gridScrollController.dispose();
    super.dispose();
  }

  void _write(String action, Future<void> Function() operation) {
    _reviewChanged = true;
    _lastReviewedAt = DateTime.now().microsecondsSinceEpoch;
    _lastWrite = _lastWrite.then((_) => operation()).catchError((
      Object e,
      StackTrace s,
    ) {
      _logger.severe("Failed to $action", e, s);
      unawaited(_recoverFromWriteFailure(e));
    });
    if (_leaving) _publishReviewChanged();
  }

  void _publishReviewChanged() {
    _leaving = true;
    if (!_reviewChanged) return;
    _reviewChanged = false;
    final summary =
        !_loaded ||
            _files.isEmpty ||
            _deleting ||
            _loadedFilesRevision != _filesRevision
        ? null
        : ReviewMonthSummary(
            key: widget.monthKey,
            cover: _files.first,
            totalCount: _files.length,
            decidedCount: _decidedCount,
            queuedCount: _queuedCount,
            markedReviewed: _record?.markedReviewed ?? false,
            lastReviewedAt: _lastReviewedAt,
          );
    widget.onReviewChanged?.call(widget.monthKey, summary, _lastWrite);
  }

  Future<void> _recoverFromWriteFailure(Object error) async {
    if (!mounted || _reportingWriteFailure) return;
    _reportingWriteFailure = true;
    try {
      await showGenericErrorDialog(context: context, error: error);
    } finally {
      _reportingWriteFailure = false;
    }
    if (mounted) await _load();
  }

  Future<void> _load({bool resetView = true}) async {
    final generation = ++_loadGeneration;
    try {
      ReviewMonthData data;
      Future<void> settled;
      int filesRevision;
      do {
        settled = _lastWrite;
        await settled;
        if (!mounted || generation != _loadGeneration) return;
        filesRevision = _filesRevision;
        data = await _service.loadMonth(widget.monthKey);
      } while (!identical(settled, _lastWrite));
      if (!mounted || generation != _loadGeneration) return;
      if (_swipeActiveNotifier.value || _swipeHelper.isActive) {
        _reloadAfterSwipe = resetView || (_reloadAfterSwipe ?? false);
        return;
      }
      setState(() {
        _files = data.files;
        _decisions
          ..clear()
          ..addAll(data.decisions);
        _record = data.record;
        _lastReviewedAt = data.record?.updatedAt ?? 0;
        _loadedFilesRevision = filesRevision;
        _loaded = true;
        _rebuildReviewState();
        _extendDeck();
        _history
          ..clear()
          ..addAll([
            for (final (file, decision) in data.history)
              (
                file,
                decision == ReviewDecision.queued
                    ? ReviewSwipeDirection.left
                    : ReviewSwipeDirection.right,
              ),
          ]);
        if (resetView ||
            _view == _ReviewMonthView.done ||
            (_view == _ReviewMonthView.grid && !_canSwipe) ||
            (_view == _ReviewMonthView.queue && _queuedCount == 0) ||
            (_view == _ReviewMonthView.swipe &&
                (_deck.isEmpty || !_canSwipe))) {
          _settleView();
        }
      });
    } catch (e, s) {
      _logger.severe("Failed to load month ${widget.monthKey}", e, s);
      if (!mounted || generation != _loadGeneration) return;
      await showGenericErrorDialog(context: context, error: e);
      if (!mounted || generation != _loadGeneration) return;
      Navigator.of(context).pop();
    }
  }

  void _onSwipeActiveChanged() {
    final resetView = _reloadAfterSwipe;
    if (_swipeActiveNotifier.value || resetView == null) return;
    _reloadAfterSwipe = null;
    unawaited(_load(resetView: resetView));
  }

  void _onFilesUpdated(FilesUpdatedEvent event) {
    _filesRevision++;
    if (_deleting) return;
    _reloadDebouncer.run(() => _load(resetView: false));
  }

  EnteFile? _loadedFile(EnteFile file) => _files.firstWhereOrNull(
    (loaded) =>
        (file.generatedID != null && loaded.generatedID == file.generatedID) ||
        (file.uploadedFileID != null &&
            loaded.uploadedFileID == file.uploadedFileID),
  );

  void _rebuildReviewState() {
    _undecided.clear();
    _queuedCount = 0;
    for (final file in _files) {
      final decision = _decisions[PhotoReviewService.fileKey(file)];
      if (decision == null) {
        _undecided.add(file);
      } else if (decision == ReviewDecision.queued) {
        _queuedCount++;
      }
    }
    final byGeneratedId = {
      for (final file in _undecided)
        if (file.generatedID != null) file.generatedID!: file,
    };
    final byUploadedId = {
      for (final file in _undecided)
        if (file.uploadedFileID != null) file.uploadedFileID!: file,
    };
    final byLocalId = {
      for (final file in _undecided)
        if (file.localID != null) file.localID!: file,
    };
    EnteFile? undecidedFile(EnteFile file) =>
        byGeneratedId[file.generatedID] ??
        byUploadedId[file.uploadedFileID] ??
        (file.isUploaded ? null : byLocalId[file.localID]);
    final deck = {for (final file in _deck) ?undecidedFile(file)};
    _deck
      ..clear()
      ..addAll(deck);
    if (_selection.files.isNotEmpty) {
      _selection.replaceSelection({
        for (final file in _selection.files) ?undecidedFile(file),
      });
    }
  }

  void _setDecision(EnteFile file, ReviewDecision? decision) {
    final key = PhotoReviewService.fileKey(file);
    if (_decisions[key] == ReviewDecision.queued) _queuedCount--;
    if (decision == null) {
      _decisions.remove(key);
    } else {
      _decisions[key] = decision;
      if (decision == ReviewDecision.queued) _queuedCount++;
    }
  }

  void _extendDeck() {
    final anchor = _deckAnchor;
    if (_deck.isEmpty || anchor == null) return;
    final loaded = _loadedFile(anchor);
    if (loaded != null) _deckAnchor = loaded;
    final anchorTime = anchor.creationTime;
    final start = loaded != null
        ? _files.indexOf(loaded)
        : anchorTime == null
        ? -1
        : _files.indexWhere((file) => (file.creationTime ?? 0) <= anchorTime);
    if (start < 0) return;
    final undecided = _undecided.toSet();
    final deck = _deck.toSet();
    final order = {for (final (index, file) in _files.indexed) file: index};
    for (final file in _files.skip(start)) {
      if (undecided.contains(file) && deck.add(file)) {
        final index = order[file]!;
        _deck.insert(
          _deck.lastIndexWhere((card) => order[card]! < index) + 1,
          file,
        );
      }
    }
  }

  bool get _canSwipe =>
      _undecided.isNotEmpty && !(_record?.markedReviewed ?? false);

  _ReviewMonthView _resolveView() {
    if (_canSwipe) return _ReviewMonthView.grid;
    if (_queuedCount > 0) return _ReviewMonthView.queue;
    return _ReviewMonthView.done;
  }

  void _settleView() {
    final inDeck =
        _view == _ReviewMonthView.swipe ||
        (_view == _ReviewMonthView.queue &&
            _queueOrigin == _ReviewMonthView.swipe);
    if (inDeck && _deck.isNotEmpty && _canSwipe) {
      _view = _ReviewMonthView.swipe;
      return;
    }
    _deck.clear();
    _deckAnchor = null;
    _queueOrigin = _ReviewMonthView.grid;
    _view = _resolveView();
  }

  void _showGrid() {
    if (_stackController.isSwipingOut) return;
    setState(() {
      _deck.clear();
      _deckAnchor = null;
      _queueOrigin = _ReviewMonthView.grid;
      _view = _ReviewMonthView.grid;
    });
  }

  Iterable<EnteFile> get _queued => _files.where(
    (file) =>
        _decisions[PhotoReviewService.fileKey(file)] == ReviewDecision.queued,
  );

  int get _decidedCount => _files.length - _undecided.length;

  List<EnteFile> get _selectedFiles =>
      _undecided.where(_selection.files.contains).toList();

  VoidCallback? get _backAction => switch (_view) {
    _ReviewMonthView.grid when _selection.files.isNotEmpty => _clearSelection,
    _ReviewMonthView.swipe when _canSwipe => _showGrid,
    _ReviewMonthView.queue
        when _queueOrigin == _ReviewMonthView.swipe && _deck.isNotEmpty =>
      () => setState(() => _view = _ReviewMonthView.swipe),
    _ReviewMonthView.queue when _canSwipe => _showGrid,
    _ => null,
  };

  void _openDeck(EnteFile file) {
    final index = _undecided.indexOf(file);
    if (index < 0) return;
    setState(() {
      _deckAnchor = file;
      _deck
        ..clear()
        ..addAll(_undecided.skip(index));
      _view = _ReviewMonthView.swipe;
    });
  }

  void _openQueue() {
    if (_stackController.isSwipingOut) return;
    setState(() {
      _queueOrigin = _view;
      _selection.clearAll(fireEvent: false);
      _view = _ReviewMonthView.queue;
    });
  }

  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  void _toggleSelection(EnteFile file) {
    unawaited(HapticFeedback.selectionClick());
    _selection.toggleSelection(file);
  }

  void _startSwipeSelection(EnteFile file) {
    final pointer = _gridPointer;
    if (pointer == null || !TouchCrossDetector.isPointerActive(pointer)) {
      _toggleSelection(file);
      return;
    }
    _swipeHelper.startSelection(file);
  }

  void _clearSelection() => _selection.clearAll(fireEvent: false);

  void _keepSelected() {
    final files = _selectedFiles;
    if (files.isEmpty) return;
    unawaited(HapticFeedback.lightImpact());
    setState(() {
      for (final file in files) {
        _setDecision(file, ReviewDecision.keep);
        _history.add((file, ReviewSwipeDirection.right));
      }
      _selection.clearAll(fireEvent: false);
      _rebuildReviewState();
      if (!_canSwipe) _settleView();
    });
    _write(
      "keep selected files",
      () =>
          _service.recordDecisions(files, widget.monthKey, ReviewDecision.keep),
    );
  }

  Future<void> _onSwiped(
    EnteFile swiped,
    ReviewSwipeDirection direction,
  ) async {
    final file = _loadedFile(swiped);
    if (file == null) return;
    setState(() {
      _setDecision(file, direction.decision);
      _undecided.remove(file);
      _deck.remove(file);
      _history.add((file, direction));
      if (_deck.isEmpty) _settleView();
    });
    _write(
      "record decision",
      () =>
          _service.recordDecisions([file], widget.monthKey, direction.decision),
    );
  }

  void _undo() {
    if (_history.isEmpty ||
        _stackController.isSwipingOut ||
        _stackController.isDragging) {
      return;
    }
    final (file, direction) = _history.removeLast();
    if (!_files.contains(file)) return;
    unawaited(HapticFeedback.lightImpact());
    setState(() {
      _setDecision(file, null);
      _rebuildReviewState();
      _deck.insert(0, file);
      _view = _ReviewMonthView.swipe;
    });
    _stackController.revealFromSide(direction);
    _write(
      "undo decision",
      () => _service.removeDecision(file, widget.monthKey),
    );
  }

  void _removeFromQueue(EnteFile file) {
    unawaited(HapticFeedback.selectionClick());
    final record = _record;
    final unmark = record != null && record.markedReviewed;
    setState(() {
      _setDecision(file, null);
      _rebuildReviewState();
      if (_queueOrigin == _ReviewMonthView.swipe) _deck.insert(0, file);
      _history.removeWhere((entry) => entry.$1 == file);
      if (unmark) _record = record.copyWith(markedReviewed: false);
      if (_queuedCount == 0) _settleView();
    });
    _write(
      "return queued file to the deck",
      () => _service.removeDecision(file, widget.monthKey),
    );
    if (unmark) {
      _write(
        "unmark month as reviewed",
        () => _service.unmarkMonthReviewed(widget.monthKey),
      );
    }
  }

  void _openViewer(List<EnteFile> files, EnteFile file) {
    unawaited(
      routeToPage(
        context,
        DetailPage(
          DetailPageConfiguration(
            List.of(files),
            files.indexOf(file),
            _tagPrefix,
            mode: DetailPageMode.minimalistic,
          ),
        ),
      ),
    );
  }

  Future<void> _deleteFiles(List<EnteFile> queued) async {
    if (queued.isEmpty || _deleting) return;
    final hasLocal = queued.any((file) => file.localID != null);
    final hasRemote =
        !isLocalGalleryMode && queued.any((file) => file.isUploaded);
    if (!hasLocal && !hasRemote) return;
    var didDeleteFiles = false;
    var deletedLocal = false;
    void recordDeletion({
      required List<EnteFile> removed,
      List<EnteFile> kept = const [],
    }) {
      if (removed.isEmpty && kept.isEmpty) return;
      didDeleteFiles = true;
      _write(
        "record deletion",
        () => _service.recordDeletion(
          widget.monthKey,
          removed: removed,
          kept: kept,
        ),
      );
    }

    _deleting = true;
    try {
      final didDelete = await showDeleteConfirmationSheet(
        context,
        files: queued,
        isLocal: hasLocal,
        isRemote: hasRemote,
        count: queued.length,
        onDeleteFromLocal: () async {
          final result = await deleteFilesOnDeviceOnly(context, queued);
          recordDeletion(
            removed: result.where((file) => !file.isUploaded).toList(),
            kept: result.where((file) => file.isUploaded).toList(),
          );
          deletedLocal = result.isNotEmpty;
          return result.isNotEmpty;
        },
        onDeleteFromRemote: () async {
          final remote = queued.where((file) => file.isUploaded).toList();
          await deleteFilesFromRemoteOnly(context, List.of(remote));
          recordDeletion(removed: remote);
          return remote.isNotEmpty;
        },
        onDeleteFromBoth: () async {
          final result = await deleteFilesFromEverywhere(context, queued);
          recordDeletion(removed: result);
          deletedLocal = result.any((file) => file.localID != null);
          return result.isNotEmpty;
        },
      );
      if (!mounted) return;
      if (didDelete == true && deletedLocal) {
        await showMediaManagementHintSheet(context);
      }
    } catch (e, s) {
      _logger.severe("Failed to free up space", e, s);
    } finally {
      _deleting = false;
    }
    if (!mounted) return;
    if (didDeleteFiles) _selection.clearAll(fireEvent: false);
    await _load(resetView: didDeleteFiles);
  }

  Future<void> _reviewNextMonth() async {
    final overview = await _service.loadOverview();
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
    final next = PhotoReviewService.nextMonthToReview(
      overview,
      widget.monthKey,
    );
    if (next == null) {
      Navigator.of(context).pop();
      return;
    }
    _publishReviewChanged();
    final page = ReviewMonthPage(
      monthKey: next,
      onReviewChanged: widget.onReviewChanged,
      pendingWritesForMonth: widget.pendingWritesForMonth,
    );
    if (Platform.isIOS) {
      unawaited(
        Navigator.of(context).pushReplacement(
          SwipeableRouteBuilder(pageBuilder: (_, _, _) => page),
        ),
      );
    } else {
      replacePage(context, page);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final locale = Localizations.localeOf(context).toString();
    final title = DateFormat.yMMMM(locale).format(widget.monthKey.start);
    final backAction = _backAction;
    return PopScope(
      canPop: backAction == null,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _publishReviewChanged();
        } else {
          _backAction?.call();
        }
      },
      child: Scaffold(
        backgroundColor: colors.backgroundBase,
        body: switch (_view) {
          _ReviewMonthView.grid => _buildGridView(context, title),
          _ReviewMonthView.swipe => _buildSwipeView(context, title),
          _ReviewMonthView.queue => _buildQueueView(context, title),
          _ReviewMonthView.done => _buildDoneView(context, title),
        },
      ),
    );
  }

  Widget _buildSwipeView(BuildContext context, String title) {
    final colors = context.componentColors;
    final l10n = context.strings;
    final padding = MediaQuery.paddingOf(context);
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final actions = [
      _RoundActionButton(
        size: _actionButtonSize,
        background: colors.fillBase,
        tooltip: l10n.delete,
        icon: HugeIcon(
          icon: HugeIcons.strokeRoundedDelete01,
          size: 28,
          strokeWidth: 2.117,
          color: colors.textReverse,
        ),
        onTap: () =>
            unawaited(_stackController.swipe(ReviewSwipeDirection.left)),
      ),
      _RoundActionButton(
        size: _undoButtonSize,
        background: colors.fillLight,
        tooltip: l10n.undo,
        enabled: _history.isNotEmpty,
        icon: HugeIcon(
          icon: HugeIcons.strokeRoundedUndo03,
          size: 21.135,
          strokeWidth: 1.554,
          color: colors.textBase,
        ),
        onTap: _undo,
      ),
      _RoundActionButton(
        size: _actionButtonSize,
        background: colors.primary,
        tooltip: l10n.keep,
        icon: HugeIcon(
          icon: HugeIcons.strokeRoundedTick02,
          size: 28,
          strokeWidth: 2.117,
          color: colors.specialWhite,
        ),
        onTap: () =>
            unawaited(_stackController.swipe(ReviewSwipeDirection.right)),
      ),
    ];
    final deck = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            Spacing.sm,
            Spacing.lg,
            0,
          ),
          child: _ProgressHeader(reviewed: _decidedCount, total: _files.length),
        ),
        const SizedBox(height: 9),
        Expanded(
          child: ReviewSwipeStack(
            files: _deck,
            controller: _stackController,
            onSwiped: _onSwiped,
            onCardTap: (file) => _openViewer(_deck, file),
            isFavorite: (file) =>
                FavoritesService.instance.isFavoriteCache(file),
          ),
        ),
      ],
    );
    final Widget body;
    if (landscape) {
      final bottom = padding.bottom + Spacing.xl;
      body = Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: deck,
          ),
          Positioned(
            top: Spacing.sm,
            bottom: bottom,
            right: padding.right + Spacing.xl,
            width: _actionButtonSize,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final action in actions.reversed) ...[
                    if (action != actions.last)
                      const SizedBox(height: Spacing.xl),
                    action,
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    } else {
      body = Column(
        children: [
          Expanded(child: deck),
          const SizedBox(height: Spacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final action in actions) ...[
                if (action != actions.first)
                  const SizedBox(width: _actionButtonSpacing),
                action,
              ],
            ],
          ),
          SizedBox(height: padding.bottom + _bottomActionInset),
        ],
      );
    }
    return AppBarComponent(
      title: title,
      physics: const NeverScrollableScrollPhysics(),
      actions: [_buildQueueAction(context)],
      slivers: [SliverFillRemaining(child: body)],
    );
  }

  Widget _buildQueueAction(BuildContext context) {
    final queuedCount = _queuedCount;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButtonComponent(
          variant: IconButtonComponentVariant.primary,
          tooltip: context.strings.itemsQueuedForDeletion,
          shouldSurfaceExecutionStates: false,
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedDelete01),
          onTap: queuedCount == 0 ? null : _openQueue,
        ),
        if (queuedCount > 0)
          Positioned(
            top: -5,
            right: -5,
            child: _QueueBadge(count: queuedCount),
          ),
      ],
    );
  }

  Widget _buildGridView(BuildContext context, String title) {
    final colors = context.componentColors;
    final l10n = context.strings;
    final files = _undecided;
    final selectionMode = _selection.files.isNotEmpty;
    final allSelected =
        selectionMode && _selection.files.length == files.length;
    final progressHeight =
        Spacing.sm + _ProgressHeader.heightOf(context) + Spacing.xxl;
    final topBoundary = SliverAppBarComponent.resolveGeometry(
      context,
      bottomHeight: _loaded ? progressHeight : 0,
    ).minExtent;
    final screenHeight = MediaQuery.sizeOf(context).height;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureSelectionBar();
      final boundaries = _boundariesKey.currentState;
      if (!mounted || boundaries == null) return;
      boundaries
        ..setScrollController(
          _gridScrollController,
          swipeActiveNotifier: _swipeActiveNotifier,
        )
        ..setTopBoundary(topBoundary)
        ..setBottomBoundary(screenHeight - _selectionBarHeight);
    });
    return GalleryBoundariesProvider(
      key: _boundariesKey,
      child: Stack(
        children: [
          SwipeSelectionWrapper(
            isEnabled: _loaded,
            swipeHelper: _swipeHelper,
            selectedFiles: _selection,
            swipeActiveNotifier: _swipeActiveNotifier,
            scrollController: _gridScrollController,
            child: Listener(
              onPointerDown: (event) => _gridPointer = event.pointer,
              onPointerUp: (_) => _onSwipeActiveChanged(),
              onPointerCancel: (_) => _onSwipeActiveChanged(),
              child: ValueListenableBuilder<bool>(
                valueListenable: _swipeActiveNotifier,
                builder: (context, isSwipeActive, _) => AppBarComponent(
                  key: const PageStorageKey("review_month_grid"),
                  controller: _gridScrollController,
                  physics: isSwipeActive
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  title: title,
                  actions: [_buildQueueAction(context)],
                  bottom: _loaded
                      ? PreferredSize(
                          preferredSize: Size.fromHeight(progressHeight),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(
                              Spacing.lg,
                              Spacing.sm,
                              Spacing.lg,
                              Spacing.xxl,
                            ),
                            child: _ProgressHeader(
                              reviewed: _decidedCount,
                              total: _files.length,
                            ),
                          ),
                        )
                      : null,
                  slivers: [
                    if (!_loaded)
                      const SliverFillRemaining(
                        child: Center(child: LoadingComponent()),
                      )
                    else
                      SliverSafeArea(
                        top: false,
                        bottom: false,
                        sliver: SliverPadding(
                          padding: EdgeInsets.only(
                            bottom: selectionMode
                                ? _selectionBarHeight
                                : MediaQuery.paddingOf(context).bottom,
                          ),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: _gridTileExtent,
                                  mainAxisSpacing: _gridSpacing,
                                  crossAxisSpacing: _gridSpacing,
                                ),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final file = files[index];
                              return SwipeSelectableFileWidget(
                                key: ValueKey(PhotoReviewService.fileKey(file)),
                                file: file,
                                selectedFiles: _selection,
                                child: ReviewGridTile(
                                  file: file,
                                  selected: _selection.files.contains(file),
                                  onTap: selectionMode
                                      ? () => _toggleSelection(file)
                                      : () => _openDeck(file),
                                  onLongPress: () => _startSwipeSelection(file),
                                ),
                              );
                            }, childCount: files.length),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedSlide(
              offset: selectionMode ? Offset.zero : const Offset(0, 1),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : Motion.slow,
              curve: Curves.easeOutCubic,
              child: IgnorePointer(
                ignoring: !selectionMode,
                child: ReviewSelectionBar(
                  key: _selectionBarKey,
                  selectedCount: _selection.files.length,
                  allSelected: allSelected,
                  onSelectAll: () {
                    unawaited(HapticFeedback.selectionClick());
                    if (allSelected) {
                      _clearSelection();
                    } else {
                      _selection.selectAll(files.toSet());
                    }
                  },
                  onClear: _clearSelection,
                  actions: [
                    SelectionSheetAction(
                      labelText: l10n.delete,
                      hugeIcon: HugeIcons.strokeRoundedDelete01,
                      isCritical: true,
                      onTap: () => _deleteFiles(_selectedFiles),
                    ),
                    SelectionSheetAction(
                      labelText: l10n.keep,
                      iconWidget: HugeIcon(
                        icon: HugeIcons.strokeRoundedCheckmarkCircle02,
                        size: 22,
                        strokeWidth: 1.5 * 24 / 22,
                        color: colors.primary,
                      ),
                      onTap: _keepSelected,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _measureSelectionBar() {
    final box =
        _selectionBarKey.currentContext?.findRenderObject() as RenderBox?;
    final height = box?.size.height ?? 0;
    if (mounted && height != _selectionBarHeight) {
      setState(() => _selectionBarHeight = height);
    }
  }

  Widget _buildQueueView(BuildContext context, String title) {
    final colors = context.componentColors;
    final l10n = context.strings;
    final queued = _queued.toList();
    return Column(
      children: [
        Expanded(
          child: AppBarComponent(
            title: title,
            subtitle: l10n.itemsQueuedForDeletion,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  Spacing.lg,
                  Spacing.xl,
                  Spacing.lg,
                  Spacing.xl,
                ),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: _queueTileExtent,
                    mainAxisSpacing: Spacing.lg,
                    crossAxisSpacing: 10,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _QueuedTile(
                      file: queued[index],
                      onTap: () => _openViewer(queued, queued[index]),
                      onRemove: () => _removeFromQueue(queued[index]),
                    ),
                    childCount: queued.length,
                  ),
                ),
              ),
            ],
          ),
        ),
        ColoredBox(
          color: colors.backgroundBase,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.xl,
                Spacing.lg,
                Spacing.xl,
                Spacing.lg,
              ),
              child: ButtonComponent(
                label: l10n.freeUpSpace,
                shouldSurfaceExecutionStates: false,
                isDisabled: queued.isEmpty,
                onTap: () => _deleteFiles(_queued.toList()),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDoneView(BuildContext context, String title) {
    final colors = context.componentColors;
    final l10n = context.strings;
    final record = _record;
    final summary = record == null || record.freedCount == 0
        ? l10n.reviewKeptEverything
        : record.freedBytes > 0
        ? l10n.reviewFreedUpSummary(
            size: formatBytes(record.freedBytes),
            count: record.freedCount,
          )
        : l10n.reviewRemovedItemsSummary(count: record.freedCount);
    return AppBarComponent(
      title: title,
      slivers: [
        SliverSafeArea(
          top: false,
          sliver: SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
              child: _ReviewCompletionAnimation(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.allCleanedUp,
                      textAlign: TextAlign.center,
                      style: TextStyles.display2.copyWith(
                        color: colors.textBase,
                      ),
                    ),
                    const SizedBox(height: Spacing.md),
                    Text(
                      summary,
                      textAlign: TextAlign.center,
                      style: TextStyles.body.copyWith(color: colors.textLight),
                    ),
                    const SizedBox(height: Spacing.xxl),
                    ButtonComponent(
                      label: l10n.reviewNextMonth,
                      onTap: _reviewNextMonth,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.reviewed, required this.total});

  static const _barHeight = 4.0;
  static const _gap = 6.0;
  static const _lineHeight = 13.0;

  final int reviewed;
  final int total;

  static double heightOf(BuildContext context) {
    final fontSize = TextStyles.tiny.fontSize!;
    final scaledFontSize = MediaQuery.textScalerOf(context).scale(fontSize);
    return _barHeight + _gap + scaledFontSize * _lineHeight / fontSize;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : reviewed / total,
            minHeight: _barHeight,
            backgroundColor: colors.fillDark,
            valueColor: AlwaysStoppedAnimation(colors.primary),
          ),
        ),
        const SizedBox(height: _gap),
        Text(
          context.strings.reviewProgressCount(reviewed: reviewed, total: total),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyles.tiny.copyWith(
            height: _lineHeight / TextStyles.tiny.fontSize!,
            color: colors.textLight,
          ),
        ),
      ],
    );
  }
}

class _QueueBadge extends StatelessWidget {
  const _QueueBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return IgnorePointer(
      child: Container(
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: colors.warning,
          borderRadius: BorderRadius.circular(19),
        ),
        alignment: Alignment.center,
        child: Text(
          count.toString(),
          style: TextStyles.tiny.copyWith(
            fontWeight: FontWeight.w700,
            height: null,
            color: colors.specialWhite,
          ),
        ),
      ),
    );
  }
}

class _RoundActionButton extends StatefulWidget {
  const _RoundActionButton({
    required this.size,
    required this.background,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
  });

  final double size;
  final Color background;
  final Widget icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool enabled;

  @override
  State<_RoundActionButton> createState() => _RoundActionButtonState();
}

class _RoundActionButtonState extends State<_RoundActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.tooltip,
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.enabled
              ? (_) => setState(() => _pressed = true)
              : null,
          onTapUp: widget.enabled
              ? (_) => setState(() => _pressed = false)
              : null,
          onTapCancel: widget.enabled
              ? () => setState(() => _pressed = false)
              : null,
          onTap: widget.enabled ? widget.onTap : null,
          child: AnimatedScale(
            scale: _pressed ? 0.95 : 1,
            duration: Motion.quick,
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: widget.enabled ? 1 : 0.5,
              duration: Motion.quick,
              child: Container(
                width: widget.size,
                height: widget.size,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: widget.background,
                  shape: BoxShape.circle,
                ),
                child: widget.icon,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QueuedTile extends StatelessWidget {
  const _QueuedTile({
    required this.file,
    required this.onTap,
    required this.onRemove,
  });

  final EnteFile file;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.only(top: Spacing.sm, right: Spacing.sm),
            child: Semantics(
              button: true,
              label: file.displayName,
              child: GestureDetector(
                onTap: onTap,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.button),
                  child: ThumbnailWidget(
                    file,
                    key: Key("review_queue_${file.tag}"),
                    shouldShowSyncStatus: false,
                    placeholderColor: colors.fillDark,
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: Semantics(
            button: true,
            label: context.strings.reviewAgain,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRemove,
              child: SizedBox.square(
                dimension: kMinInteractiveDimension,
                child: Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.warning,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colors.specialWhite,
                        width: 1.5,
                      ),
                    ),
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedCancel01,
                      size: 12,
                      strokeWidth: 3,
                      color: colors.specialWhite,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewCompletionAnimation extends StatelessWidget {
  const _ReviewCompletionAnimation({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final illustration = RepaintBoundary(
      child: FittedBox(
        child: SvgPicture.asset(
          "assets/photo_review/all_cleaned_up.svg",
          width: 335,
          height: 133.41,
        ),
      ),
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: reduceMotion ? Duration.zero : Motion.slow * 3,
      child: child,
      builder: (context, value, child) {
        final progress = reduceMotion ? 1.0 : value;
        final entrance = const Interval(
          0,
          0.65,
          curve: Curves.easeOutCubic,
        ).transform(progress);
        final scale = const Interval(
          0,
          0.7,
          curve: Curves.easeOutBack,
        ).transform(progress);
        final content = const Interval(
          0.18,
          1,
          curve: Curves.easeOutCubic,
        ).transform(progress);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Opacity(
              opacity: entrance,
              child: Transform.translate(
                offset: Offset(0, Spacing.lg * (1 - entrance)),
                child: Transform.scale(
                  scale: 0.82 + 0.18 * scale,
                  child: illustration,
                ),
              ),
            ),
            const SizedBox(height: Spacing.xxl),
            Opacity(
              opacity: content,
              child: Transform.translate(
                offset: Offset(0, Spacing.md * (1 - content)),
                child: child,
              ),
            ),
          ],
        );
      },
    );
  }
}
