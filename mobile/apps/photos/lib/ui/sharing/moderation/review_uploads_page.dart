import 'dart:async';

import 'package:dio/dio.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_components/hugeicons.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/services/pending_uploads_service.dart';
import 'package:photos/services/sync/remote_sync_service.dart';
import 'package:photos/theme/ente_theme.dart';
import 'package:photos/ui/components/bottom_action_bar/action_bar_widget.dart';
import 'package:photos/ui/components/bottom_action_bar/selection_action_sheet.dart';
import 'package:photos/ui/tools/photo_review/widgets/review_swipe_stack.dart';
import 'package:photos/ui/viewer/actions/select_all_status_icon.dart';
import 'package:photos/ui/viewer/file/thumbnail_widget.dart';
import 'package:photos/utils/dialog_util.dart';

class ReviewUploadsPage extends StatefulWidget {
  const ReviewUploadsPage(this.collection, {super.key});

  final Collection collection;

  @override
  State<ReviewUploadsPage> createState() => _ReviewUploadsPageState();
}

enum _View { grid, cards, choices, done }

class _ReviewUploadsPageState extends State<ReviewUploadsPage> {
  static const _actionButtonSize = 60.0;
  static const _undoButtonSize = 46.0;
  static const _actionButtonSpacing = 40.0;
  static const _bottomActionInset = 25.0;
  static const _queueTileExtent = 120.0;

  final _logger = Logger('ReviewUploadsPage');
  final _service = PendingUploadsService.instance;
  final _stack = ReviewSwipeStackController();
  final _selected = <int>{};
  late final ReviewQueue _queue = _service.reviewQueue(widget.collection.id);
  List<PendingUpload> _files = [];
  _View _view = _View.grid;
  (int, int) _result = (0, 0);
  bool _loading = true;
  bool _sending = false;
  bool _allowExit = false;
  String? _error;
  int? _cardStartID;

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
  }

  Future<void> _refresh({bool reload = false}) async {
    setState(() {
      _loading = _files.isEmpty;
      _error = null;
    });
    final reviewSession = _service.session;
    try {
      if (reload) await _service.resync(widget.collection.id);
      final files = await _service.files(widget.collection.id);
      if (!mounted || reviewSession != _service.session) return;
      _queue.retain(files.map((upload) => upload.file.uploadedFileID!));
      await _service.saveReviewQueue(widget.collection.id, _queue);
      if (!mounted) return;
      setState(() {
        _files = files;
        _selected.removeWhere(
          (id) => !files.any((upload) => upload.file.uploadedFileID == id),
        );
        _loading = false;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      if (error.response?.statusCode == 403) {
        _allowExit = true;
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _error = context.strings.reviewUploadsOffline;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = context.strings.somethingWentWrong;
        _loading = false;
      });
    }
  }

  Future<void> _choose(int id, ReviewChoice choice) async {
    _queue.choose(id, choice);
    await _service.saveReviewQueue(widget.collection.id, _queue);
    if (!mounted) return;
    setState(() {
      if (_undecided.isEmpty) _view = _View.choices;
    });
  }

  void _openSwipeView(int id) {
    setState(() {
      _cardStartID = id;
      _view = _undecided.isNotEmpty ? _View.cards : _View.choices;
    });
  }

  Future<void> _undo() async {
    _queue.undo();
    await _service.saveReviewQueue(widget.collection.id, _queue);
    if (mounted) setState(() {});
  }

  List<int> _queued(ReviewChoice choice) => _queue.choices.entries
      .where((entry) => entry.value == choice)
      .map((entry) => entry.key)
      .toList();

  void _backFromCards() {
    if (_queue.choices.isEmpty) {
      setState(() => _view = _View.grid);
    } else {
      unawaited(_finish());
    }
  }

  void _backFromChoices() =>
      setState(() => _view = _undecided.isEmpty ? _View.grid : _View.cards);

  Future<void> _finish() async {
    final l10n = context.strings;
    await showBottomSheetComponent<void>(
      context: context,
      builder: (sheetContext) => BottomSheetComponent(
        title: l10n.finishThisReview,
        closeTooltip: l10n.close,
        content: Text(
          l10n.reviewChoiceCounts(
            approveCount: _queue.approveCount,
            rejectCount: _queue.rejectCount,
          ),
          textAlign: TextAlign.center,
          style: TextStyles.body.copyWith(
            color: sheetContext.componentColors.textLight,
          ),
        ),
        actions: [
          ButtonComponent(
            label: l10n.reviewChoices,
            onTap: () {
              Navigator.of(sheetContext).pop();
              setState(() => _view = _View.choices);
            },
          ),
          ButtonComponent(
            label: l10n.continueLater,
            variant: ButtonComponentVariant.secondary,
            onTap: () {
              Navigator.of(sheetContext).pop();
              _allowExit = true;
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _send(Map<ReviewChoice, List<int>> choices) async {
    if (_sending) return;
    setState(() => _sending = true);
    final reviewSession = _service.session;
    var sent = false;
    try {
      for (final MapEntry(key: choice, value: ids) in choices.entries) {
        for (
          var start = 0;
          start < ids.length;
          start += PendingUploadsService.submitBatchSize
        ) {
          final batch = ids
              .skip(start)
              .take(PendingUploadsService.submitBatchSize)
              .toList();
          if (reviewSession != _service.session) return;
          await _service.submit(widget.collection.id, choice.name, batch);
          if (reviewSession != _service.session) return;
          _queue.remove(batch);
          await _service.saveReviewQueue(widget.collection.id, _queue);
        }
      }
      sent = true;
    } on DioException catch (error) {
      if (!mounted) return;
      if (error.response?.statusCode == 403) {
        _allowExit = true;
        Navigator.of(context).pop();
        return;
      }
      await showGenericErrorDialog(context: context, error: error);
    } catch (error, stack) {
      _logger.warning('Failed to submit review', error, stack);
      if (mounted) await showGenericErrorDialog(context: context, error: error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    try {
      await RemoteSyncService.instance.syncCollection(widget.collection.id);
    } catch (error, stack) {
      _logger.warning('Failed to sync reviewed files', error, stack);
    }
    final files = await _service.files(widget.collection.id);
    if (!mounted) return;
    setState(() {
      _files = files;
      if (sent) {
        _result = (
          choices[ReviewChoice.approve]?.length ?? 0,
          choices[ReviewChoice.reject]?.length ?? 0,
        );
        _view = _View.done;
      }
    });
  }

  Future<void> _confirmSelected(ReviewChoice choice) async {
    final ids = _selected.toList();
    final approve = choice == ReviewChoice.approve;
    final ok = await _confirm(
      approveCount: approve ? ids.length : 0,
      rejectCount: approve ? 0 : ids.length,
    );
    if (ok != true || !mounted) return;
    setState(_selected.clear);
    await _send({choice: ids});
  }

  Future<void> _confirmChoices() async {
    final approved = _queued(ReviewChoice.approve);
    final rejected = _queued(ReviewChoice.reject);
    final ok = await _confirm(
      approveCount: approved.length,
      rejectCount: rejected.length,
    );
    if (ok != true) return;
    await _send({
      ReviewChoice.approve: approved,
      ReviewChoice.reject: rejected,
    });
  }

  Future<bool?> _confirm({
    required int approveCount,
    required int rejectCount,
  }) {
    final l10n = context.strings;
    final owner = widget.collection.isOwner(
      Configuration.instance.getUserID()!,
    );
    final rejectOnly = approveCount == 0;
    final approveOnly = rejectCount == 0;
    final message = [
      if (approveCount > 0)
        l10n.reviewApprovalVisibility(
          count: approveCount,
          albumName: widget.collection.displayName,
        ),
      if (rejectCount > 0)
        owner ? l10n.reviewOwnerTrashRecovery : l10n.reviewAdminTrashRecovery,
    ].join('\n');
    return showBottomSheetComponent<bool>(
      context: context,
      builder: (sheetContext) => BottomSheetComponent(
        title: approveOnly
            ? l10n.approvePhotosQuestion(count: approveCount)
            : rejectOnly
            ? l10n.rejectPhotosQuestion(count: rejectCount)
            : l10n.reviewChoices,
        illustration: rejectOnly ? Image.asset('assets/warning-red.png') : null,
        closeTooltip: l10n.close,
        content: Text(
          approveOnly || rejectOnly
              ? message
              : '${l10n.reviewChoiceCounts(approveCount: approveCount, rejectCount: rejectCount)}\n$message',
          textAlign: TextAlign.center,
          style: TextStyles.body.copyWith(
            color: sheetContext.componentColors.textLight,
          ),
        ),
        actions: [
          ButtonComponent(
            label: approveOnly
                ? l10n.approvePhotos(count: approveCount)
                : rejectOnly
                ? l10n.rejectPhotos(count: rejectCount)
                : l10n.confirm,
            variant: rejectOnly
                ? ButtonComponentVariant.critical
                : ButtonComponentVariant.primary,
            onTap: () => Navigator.of(sheetContext).pop(true),
          ),
          ButtonComponent(
            label: l10n.cancel,
            variant: ButtonComponentVariant.secondary,
            onTap: () => Navigator.of(sheetContext).pop(false),
          ),
        ],
      ),
    );
  }

  List<EnteFile> get _undecided {
    final undecided = _files
        .where(
          (upload) => !_queue.choices.containsKey(upload.file.uploadedFileID),
        )
        .map((upload) => upload.file)
        .toList();
    final start = undecided.indexWhere(
      (file) => file.uploadedFileID == _cardStartID,
    );
    if (start > 0) undecided.insert(0, undecided.removeAt(start));
    return undecided;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return PopScope(
      canPop:
          _allowExit ||
          _view == _View.done ||
          (_view == _View.grid && _queue.choices.isEmpty),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_view == _View.choices) {
          _backFromChoices();
        } else {
          _backFromCards();
        }
      },
      child: Scaffold(
        backgroundColor: colors.backgroundBase,
        body: _loading
            ? const Center(child: LoadingComponent())
            : switch (_view) {
                _View.grid => _buildGridView(context),
                _View.cards => _buildSwipeView(context),
                _View.choices => _buildChoicesView(context),
                _View.done => _buildDoneView(context),
              },
      ),
    );
  }

  List<List<PendingUpload>> get _sessions {
    final result = <List<PendingUpload>>[];
    for (final upload in _files) {
      if (result.isEmpty ||
          result.last.last.createdAt - upload.createdAt >
              const Duration(minutes: 30).inMicroseconds) {
        result.add([upload]);
      } else {
        result.last.add(upload);
      }
    }
    return result;
  }

  Widget _buildGridView(BuildContext context) {
    final colors = context.componentColors;
    final l10n = context.strings;
    final selectionMode = _selected.isNotEmpty;
    final allSelected = _selected.length == _files.length;
    final locale = Localizations.localeOf(context).toString();
    return Stack(
      children: [
        AppBarComponent(
          title: l10n.reviewUploads,
          subtitle:
              '${widget.collection.displayName} · ${l10n.photosCount(count: _files.length)}',
          actions: [
            IconButtonComponent(
              variant: IconButtonComponentVariant.primary,
              shouldSurfaceExecutionStates: false,
              tooltip: l10n.refreshUploads,
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh),
              onTap: _sending ? null : () => _refresh(reload: true),
            ),
          ],
          slivers: [
            if (_files.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _error != null
                    ? _buildMessage(
                        context,
                        message: _error!,
                        button: l10n.retry,
                        onTap: _refresh,
                      )
                    : _buildMessage(
                        context,
                        title: l10n.noPhotosToReview,
                        message: l10n.newUploadsAppearHere,
                        button: l10n.backToAlbum,
                        onTap: () => Navigator.of(context).pop(),
                      ),
              )
            else
              for (final session in _sessions) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                  sliver: SliverToBoxAdapter(
                    child: _SessionHeader(
                      label: DateFormat.MMMd(locale).add_jm().format(
                        DateTime.fromMicrosecondsSinceEpoch(
                          session.first.createdAt,
                        ),
                      ),
                      selected: _selected.containsAll(
                        session.map((upload) => upload.file.uploadedFileID!),
                      ),
                      onTap: () => setState(() {
                        final ids = session.map(
                          (upload) => upload.file.uploadedFileID!,
                        );
                        if (_selected.containsAll(ids)) {
                          _selected.removeAll(ids);
                        } else {
                          _selected.addAll(ids);
                        }
                      }),
                    ),
                  ),
                ),
                SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 2,
                    crossAxisSpacing: 2,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final file = session[index].file;
                    final id = file.uploadedFileID!;
                    return _UploadTile(
                      file: file,
                      selected: _selected.contains(id),
                      onLongPress: () => setState(() => _selected.add(id)),
                      onTap: selectionMode
                          ? () => setState(() {
                              if (!_selected.add(id)) _selected.remove(id);
                            })
                          : () => _openSwipeView(id),
                    );
                  }, childCount: session.length),
                ),
              ],
            SliverToBoxAdapter(
              child: SizedBox(
                height: selectionMode
                    ? 200
                    : MediaQuery.paddingOf(context).bottom,
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: AnimatedSlide(
            offset: selectionMode ? Offset.zero : const Offset(0, 1),
            duration: Motion.slow,
            curve: Curves.easeOutCubic,
            child: IgnorePointer(
              ignoring: !selectionMode,
              child: SelectionActionSheet(
                actions: [
                  SelectionSheetAction(
                    labelText: l10n.reject,
                    hugeIcon: HugeIcons.strokeRoundedDelete01,
                    isCritical: true,
                    onTap: () =>
                        unawaited(_confirmSelected(ReviewChoice.reject)),
                  ),
                  SelectionSheetAction(
                    labelText: l10n.approve,
                    hugeIcon: HugeIcons.strokeRoundedTick02,
                    onTap: () =>
                        unawaited(_confirmSelected(ReviewChoice.approve)),
                  ),
                ],
                selectionControls: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: SelectionControlChip(
                          label: l10n.selectAllShort,
                          semanticLabel: l10n.selectAll,
                          isSelected: allSelected,
                          icon: SelectAllStatusIcon(
                            isSelected: allSelected,
                            size: IconSizes.small,
                            unselectedColor: colors.textLighter,
                          ),
                          onTap: () => setState(() {
                            if (allSelected) {
                              _selected.clear();
                            } else {
                              _selected.addAll(
                                _files.map(
                                  (upload) => upload.file.uploadedFileID!,
                                ),
                              );
                            }
                          }),
                        ),
                      ),
                      const SizedBox(width: Spacing.sm),
                      Flexible(
                        child: SelectionControlChip(
                          label: _selected.length.toString(),
                          semanticLabel:
                              '${l10n.cancel}, ${l10n.selectedPhotos(count: _selected.length)}',
                          icon: const HugeIcon(
                            icon: HugeIcons.strokeRoundedCancel01,
                          ),
                          onTap: () => setState(_selected.clear),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSwipeView(BuildContext context) {
    final colors = context.componentColors;
    final l10n = context.strings;
    final undecided = _undecided;
    final padding = MediaQuery.paddingOf(context);
    final queuedCount = _queue.choices.length;
    final actions = [
      _RoundActionButton(
        size: _actionButtonSize,
        background: colors.warning,
        tooltip: l10n.reject,
        enabled: undecided.isNotEmpty,
        icon: HugeIcon(
          icon: HugeIcons.strokeRoundedDelete01,
          size: 28,
          strokeWidth: 2.117,
          color: colors.specialWhite,
        ),
        onTap: () => unawaited(_stack.swipe(ReviewSwipeDirection.left)),
      ),
      _RoundActionButton(
        size: _undoButtonSize,
        background: colors.fillLight,
        tooltip: l10n.undo,
        enabled: _queue.choices.isNotEmpty,
        icon: HugeIcon(
          icon: HugeIcons.strokeRoundedUndo03,
          size: 21.135,
          strokeWidth: 1.554,
          color: colors.textBase,
        ),
        onTap: () => unawaited(_undo()),
      ),
      _RoundActionButton(
        size: _actionButtonSize,
        background: colors.primary,
        tooltip: l10n.approve,
        enabled: undecided.isNotEmpty,
        icon: HugeIcon(
          icon: HugeIcons.strokeRoundedTick02,
          size: 28,
          strokeWidth: 2.117,
          color: colors.specialWhite,
        ),
        onTap: () => unawaited(_stack.swipe(ReviewSwipeDirection.right)),
      ),
    ];
    return AppBarComponent(
      title: l10n.reviewUploads,
      physics: const NeverScrollableScrollPhysics(),
      onBack: _backFromCards,
      actions: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButtonComponent(
              variant: IconButtonComponentVariant.primary,
              tooltip: l10n.reviewChoices,
              shouldSurfaceExecutionStates: false,
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedDelete01),
              onTap: queuedCount == 0
                  ? null
                  : () => setState(() => _view = _View.choices),
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
          child: Column(
            children: [
              const SizedBox(height: Spacing.sm),
              Expanded(
                child: undecided.isEmpty
                    ? _buildMessage(
                        context,
                        title: l10n.noPhotosToReview,
                        button: l10n.reviewChoices,
                        onTap: () => setState(() => _view = _View.choices),
                      )
                    : ReviewSwipeStack(
                        files: undecided,
                        controller: _stack,
                        isFavorite: (_) => false,
                        onCardTap: (_) {},
                        onSwiped: (file, direction) => _choose(
                          file.uploadedFileID!,
                          direction == ReviewSwipeDirection.right
                              ? ReviewChoice.approve
                              : ReviewChoice.reject,
                        ),
                      ),
              ),
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
          ),
        ),
      ],
    );
  }

  Widget _buildChoicesView(BuildContext context) {
    final colors = context.componentColors;
    final l10n = context.strings;
    final chosen = _files
        .map((upload) => upload.file)
        .where((file) => _queue.choices.containsKey(file.uploadedFileID))
        .toList();
    return Column(
      children: [
        Expanded(
          child: AppBarComponent(
            title: l10n.reviewChoices,
            subtitle: l10n.reviewChoiceCounts(
              approveCount: _queue.approveCount,
              rejectCount: _queue.rejectCount,
            ),
            onBack: _backFromChoices,
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
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final file = chosen[index];
                    final id = file.uploadedFileID!;
                    return _QueuedTile(
                      file: file,
                      approved: _queue.choices[id] == ReviewChoice.approve,
                      onRemove: () {
                        _queue.remove([id]);
                        unawaited(
                          _service.saveReviewQueue(
                            widget.collection.id,
                            _queue,
                          ),
                        );
                        if (_queue.choices.isEmpty) {
                          _backFromChoices();
                        } else {
                          setState(() {});
                        }
                      },
                    );
                  }, childCount: chosen.length),
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
                label: l10n.confirm,
                shouldSurfaceExecutionStates: false,
                isDisabled: _sending || chosen.isEmpty,
                onTap: _confirmChoices,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDoneView(BuildContext context) {
    final l10n = context.strings;
    final (approved, rejected) = _result;
    final owner = widget.collection.isOwner(
      Configuration.instance.getUserID()!,
    );
    final remaining = _files.isNotEmpty;
    return AppBarComponent(
      title: l10n.reviewUploads,
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildMessage(
            context,
            title: rejected == 0
                ? l10n.photosApproved
                : approved == 0
                ? l10n.photosRejected
                : l10n.photosReviewed,
            message: [
              l10n.reviewCompletedCounts(
                approveCount: approved,
                rejectCount: rejected,
              ),
              if (rejected > 0)
                owner
                    ? l10n.reviewOwnerTrashRecovery
                    : l10n.reviewAdminTrashRecovery,
            ].join('. '),
            button: remaining ? l10n.continueReview : l10n.backToAlbum,
            onTap: remaining
                ? () => setState(() => _view = _View.grid)
                : () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }

  Widget _buildMessage(
    BuildContext context, {
    String? title,
    String? message,
    required String button,
    required VoidCallback onTap,
  }) {
    final colors = context.componentColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          HugeIcon(
            icon: HugeIcons.strokeRoundedShield01,
            size: 40,
            color: colors.primary,
          ),
          const SizedBox(height: Spacing.lg),
          if (title != null)
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyles.h2.copyWith(color: colors.textBase),
            ),
          if (message != null) ...[
            const SizedBox(height: Spacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyles.body.copyWith(color: colors.textLight),
            ),
          ],
          const SizedBox(height: Spacing.xl),
          ButtonComponent(
            label: button,
            variant: ButtonComponentVariant.secondary,
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}

class _SessionHeader extends StatelessWidget {
  const _SessionHeader({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyles.body.copyWith(
              color: getEnteColorScheme(context).textMuted,
            ),
          ),
        ),
        Semantics(
          button: true,
          label: context.strings.selectAll,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox.square(
              dimension: kMinInteractiveDimension,
              child: Center(
                child: SelectAllStatusIcon(
                  isSelected: selected,
                  size: IconSizes.small,
                  selectedFillColor: colors.primary,
                  unselectedColor: colors.textLighter,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UploadTile extends StatelessWidget {
  const _UploadTile({
    required this.file,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final EnteFile file;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ThumbnailWidget(
            file,
            key: Key('review_uploads_${file.tag}'),
            shouldShowSyncStatus: false,
            shouldShowFavoriteIcon: false,
            placeholderColor: colors.fillDark,
          ),
          if (selected)
            Positioned(
              top: Spacing.sm,
              right: Spacing.sm,
              child: SelectAllStatusIcon(
                isSelected: true,
                size: IconSizes.small,
                selectedFillColor: colors.primary,
              ),
            ),
        ],
      ),
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
    required this.approved,
    required this.onRemove,
  });

  final EnteFile file;
  final bool approved;
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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.button),
              child: ThumbnailWidget(
                file,
                key: Key('review_choice_${file.tag}'),
                shouldShowSyncStatus: false,
                placeholderColor: colors.fillDark,
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: Semantics(
            button: true,
            label: context.strings.remove,
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
                      color: approved ? colors.primary : colors.warning,
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
