import "dart:async";
import "dart:io";
import "dart:math" as math;

import "package:collection/collection.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:hugeicons/hugeicons.dart";
import "package:intl/intl.dart";
import "package:logging/logging.dart";
import "package:photos/core/event_bus.dart";
import "package:photos/events/files_updated_event.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/photo_review/photo_review_models.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/favorites_service.dart";
import "package:photos/services/photo_review/photo_review_service.dart";
import "package:photos/ui/tools/photo_review/widgets/review_swipe_stack.dart";
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/utils/delete_file_util.dart";
import "package:photos/utils/dialog_util.dart";

enum _ReviewMonthView { swipe, queue, done }

class ReviewMonthPage extends StatefulWidget {
  const ReviewMonthPage({required this.monthKey, super.key});

  final ReviewMonthKey monthKey;

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

  final _service = PhotoReviewService.instance;
  final _stackController = ReviewSwipeStackController();
  late final StreamSubscription<FilesUpdatedEvent> _filesSubscription;

  List<EnteFile> _files = [];
  final Map<String, ReviewDecision> _decisions = {};
  final List<EnteFile> _undecided = [];
  final List<(EnteFile, ReviewSwipeDirection)> _history = [];
  ReviewMonthRecord? _record;
  Future<void> _lastWrite = Future.value();
  int _loadGeneration = 0;
  bool _loaded = false;
  bool _deleting = false;
  bool _reportingWriteFailure = false;
  _ReviewMonthView _view = _ReviewMonthView.swipe;

  @override
  void initState() {
    super.initState();
    _filesSubscription = Bus.instance.on<FilesUpdatedEvent>().listen(
      _onFilesUpdated,
    );
    unawaited(_load());
  }

  @override
  void dispose() {
    _filesSubscription.cancel();
    super.dispose();
  }

  void _write(String action, Future<void> Function() operation) {
    _lastWrite = _lastWrite.then((_) => operation()).catchError((
      Object e,
      StackTrace s,
    ) {
      _logger.severe("Failed to $action", e, s);
      unawaited(_recoverFromWriteFailure(e));
    });
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
      do {
        settled = _lastWrite;
        await settled;
        data = await _service.loadMonth(widget.monthKey);
      } while (!identical(settled, _lastWrite));
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _files = data.files;
        _decisions
          ..clear()
          ..addAll(data.decisions);
        _record = data.record;
        _loaded = true;
        _rebuildUndecided();
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
            (_view == _ReviewMonthView.queue && _queued.isEmpty) ||
            (_view == _ReviewMonthView.swipe && !_canSwipe)) {
          _view = _resolveView();
        }
      });
    } catch (e, s) {
      _logger.severe("Failed to load month ${widget.monthKey}", e, s);
      if (!mounted) return;
      await showGenericErrorDialog(context: context, error: e);
      if (mounted) Navigator.of(context).pop();
    }
  }

  void _onFilesUpdated(FilesUpdatedEvent event) {
    if (!_loaded || _deleting) return;
    final affected = event.type == EventType.addedOrUpdated
        ? event.updatedFiles.any(_outdatesDeck)
        : event.updatedFiles.any(
            (file) => _loadedFile(file) != null || _isInMonth(file),
          );
    if (affected) unawaited(_load(resetView: false));
  }

  bool _outdatesDeck(EnteFile file) {
    final loaded = _loadedFile(file);
    if (loaded == null) return _isInMonth(file);
    if (!_isInMonth(file)) return true;
    return loaded.uploadedFileID == null && file.uploadedFileID != null;
  }

  EnteFile? _loadedFile(EnteFile file) => _files.firstWhereOrNull(
    (loaded) =>
        (file.generatedID != null && loaded.generatedID == file.generatedID) ||
        (file.uploadedFileID != null &&
            loaded.uploadedFileID == file.uploadedFileID) ||
        (file.localID != null && loaded.localID == file.localID),
  );

  bool _isInMonth(EnteFile file) {
    final creationTime = file.creationTime;
    return creationTime != null &&
        creationTime >= widget.monthKey.startMicros &&
        creationTime <= widget.monthKey.endMicros;
  }

  void _rebuildUndecided() {
    _undecided
      ..clear()
      ..addAll(
        _files.where(
          (file) => !_decisions.containsKey(PhotoReviewService.fileKey(file)),
        ),
      );
  }

  bool get _canSwipe =>
      _undecided.isNotEmpty && !(_record?.markedReviewed ?? false);

  _ReviewMonthView _resolveView() {
    if (_canSwipe) return _ReviewMonthView.swipe;
    if (_queued.isNotEmpty) return _ReviewMonthView.queue;
    return _ReviewMonthView.done;
  }

  List<EnteFile> get _queued => [
    for (final file in _files)
      if (_decisions[PhotoReviewService.fileKey(file)] == ReviewDecision.queued)
        file,
  ];

  int get _decidedCount => _files.length - _undecided.length;

  Future<void> _onSwiped(EnteFile swiped, ReviewSwipeDirection direction) async {
    final file = _loadedFile(swiped);
    if (file == null) return;
    setState(() {
      _decisions[PhotoReviewService.fileKey(file)] = direction.decision;
      _undecided.remove(file);
      _history.add((file, direction));
      if (!_canSwipe) _view = _resolveView();
    });
    _write(
      "record decision",
      () => _service.recordDecision(file, widget.monthKey, direction.decision),
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
      _decisions.remove(PhotoReviewService.fileKey(file));
      _undecided.insert(0, file);
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
      _decisions.remove(PhotoReviewService.fileKey(file));
      _undecided.insert(0, file);
      _history.removeWhere((entry) => entry.$1 == file);
      if (unmark) _record = record.copyWith(markedReviewed: false);
      if (_queued.isEmpty) _view = _resolveView();
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

  Future<void> _freeUpSpace() async {
    final queued = _queued;
    if (queued.isEmpty || _deleting) return;
    final hasLocal = queued.any((file) => file.localID != null);
    final hasRemote =
        !isLocalGalleryMode && queued.any((file) => file.isUploaded);
    if (!hasLocal && !hasRemote) return;
    final removed = <EnteFile>[];
    final kept = <EnteFile>[];
    var deletedLocal = false;
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
          kept.addAll(result.where((file) => file.isUploaded));
          removed.addAll(result.where((file) => !file.isUploaded));
          deletedLocal = result.isNotEmpty;
          return result.isNotEmpty;
        },
        onDeleteFromRemote: () async {
          final remote = queued.where((file) => file.isUploaded).toList();
          await deleteFilesFromRemoteOnly(context, List.of(remote));
          removed.addAll(remote);
          return remote.isNotEmpty;
        },
        onDeleteFromBoth: () async {
          final result = await deleteFilesFromEverywhere(context, queued);
          removed.addAll(result);
          deletedLocal = result.any((file) => file.localID != null);
          return result.isNotEmpty;
        },
      );
      if (removed.isNotEmpty || kept.isNotEmpty) {
        _write(
          "record deletion",
          () => _service.recordDeletion(
            widget.monthKey,
            removed: removed,
            kept: kept,
          ),
        );
      }
      if (!mounted) return;
      if (didDelete == true && deletedLocal) {
        await showMediaManagementHintSheet(context);
      }
    } catch (e, s) {
      _logger.severe("Failed to free up space", e, s);
    } finally {
      _deleting = false;
    }
    if (mounted) await _load(resetView: removed.isNotEmpty || kept.isNotEmpty);
  }

  Future<void> _reviewNextMonth() async {
    final overview = await _service.loadOverview();
    if (!mounted) return;
    final next = PhotoReviewService.nextMonthToReview(
      overview,
      widget.monthKey,
    );
    if (next == null) {
      Navigator.of(context).pop();
      return;
    }
    final page = ReviewMonthPage(monthKey: next);
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
    final canReturnToSwipe = _view == _ReviewMonthView.queue && _canSwipe;
    return PopScope(
      canPop: !canReturnToSwipe,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _view = _ReviewMonthView.swipe);
      },
      child: Scaffold(
        backgroundColor: colors.backgroundBase,
        body: switch (_view) {
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
    final queuedCount = _queued.length;
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
            files: _undecided,
            controller: _stackController,
            onSwiped: _onSwiped,
            onCardTap: (file) => _openViewer(_undecided, file),
            isFavorite: (file) =>
                FavoritesService.instance.isFavoriteCache(file),
          ),
        ),
      ],
    );
    final Widget body;
    if (landscape) {
      final bottom = math.max(padding.bottom, Spacing.xl);
      body = Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: bottom),
            child: deck,
          ),
          Positioned(
            top: Spacing.sm,
            bottom: bottom,
            right: math.max(padding.right, Spacing.xl),
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
          SizedBox(height: math.max(padding.bottom, _bottomActionInset)),
        ],
      );
    }
    return AppBarComponent(
      title: title,
      physics: const NeverScrollableScrollPhysics(),
      actions: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButtonComponent(
              variant: IconButtonComponentVariant.primary,
              tooltip: l10n.itemsQueuedForDeletion,
              shouldSurfaceExecutionStates: false,
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedDelete01),
              onTap: queuedCount == 0
                  ? null
                  : () => setState(() => _view = _ReviewMonthView.queue),
            ),
            if (queuedCount > 0)
              Positioned(
                top: -5,
                right: -5,
                child: _QueueBadge(count: queuedCount),
              ),
          ],
        ),
      ],
      slivers: [
        SliverFillRemaining(
          child: !_loaded ? const Center(child: LoadingComponent()) : body,
        ),
      ],
    );
  }

  Widget _buildQueueView(BuildContext context, String title) {
    final colors = context.componentColors;
    final l10n = context.strings;
    final queued = _queued;
    return Column(
      children: [
        Expanded(
          child: AppBarComponent(
            title: title,
            subtitle: l10n.itemsQueuedForDeletion,
            onBack: _canSwipe
                ? () => setState(() => _view = _ReviewMonthView.swipe)
                : null,
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
                onTap: _freeUpSpace,
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _CleanedUpIllustration(),
                  const SizedBox(height: Spacing.xxl),
                  Text(
                    l10n.allCleanedUp,
                    textAlign: TextAlign.center,
                    style: TextStyles.display2.copyWith(color: colors.textBase),
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
      ],
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.reviewed, required this.total});

  final int reviewed;
  final int total;

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
            minHeight: 4,
            backgroundColor: colors.fillDark,
            valueColor: AlwaysStoppedAnimation(colors.primary),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          context.strings.reviewProgressCount(reviewed: reviewed, total: total),
          style: TextStyles.tiny.copyWith(
            height: 13 / 10,
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
        Positioned(
          top: -5 - Spacing.sm,
          right: -6 - Spacing.sm,
          child: Semantics(
            button: true,
            label: context.strings.reviewAgain,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onRemove,
              child: Padding(
                padding: const EdgeInsets.all(Spacing.sm),
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.warning,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.specialWhite, width: 1.5),
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
      ],
    );
  }
}

class _CleanedUpIllustration extends StatelessWidget {
  const _CleanedUpIllustration();

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      child: SizedBox(
        width: 335,
        height: 133.41,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            SvgPicture.asset(
              "assets/photo_review/all_cleaned_up.svg",
              width: 335,
              height: 133.41,
            ),
            Positioned(
              left: 93,
              top: 33,
              child: Transform.rotate(
                angle: 62.92 * math.pi / 180,
                child: SvgPicture.asset(
                  "assets/photo_review/sparkle.svg",
                  width: 13.6,
                  height: 13.6,
                  colorFilter: const ColorFilter.mode(
                    Color(0xFFF4D93B),
                    BlendMode.srcIn,
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
