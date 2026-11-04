import "dart:math" as math;

import "package:ente_components/components/chip_surface.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:hugeicons/hugeicons.dart";
import "package:intl/intl.dart";
import "package:photos/models/photo_review/photo_review_models.dart";
import "package:photos/ui/tools/photo_review/widgets/review_month_card.dart";
import "package:photos/ui/viewer/actions/select_all_status_icon.dart";

class ReviewYearSection extends StatelessWidget {
  const ReviewYearSection({
    required this.year,
    required this.selectedMonths,
    required this.expanded,
    required this.onMonthTap,
    required this.onMonthLongPress,
    required this.onYearToggle,
    required this.onExpandedChanged,
    super.key,
  });

  static const double _slotWidth = 90.205;
  static const double _slotHeight = 124.927;
  static const double _rowSpacing = 32;
  static const double _minSlotGap = 12;
  static const double _tiltDegrees = 2;

  static int _slotsPerRow(double width) {
    final usable = width - Spacing.sm * 2 + _minSlotGap;
    return math.max(1, (usable / (_slotWidth + _minSlotGap)).floor());
  }

  final ReviewYearSummary year;
  final Set<ReviewMonthKey> selectedMonths;
  final bool expanded;
  final ValueChanged<ReviewMonthSummary> onMonthTap;
  final ValueChanged<ReviewMonthSummary> onMonthLongPress;
  final VoidCallback onYearToggle;
  final ValueChanged<bool> onExpandedChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;
    final colors = context.componentColors;
    final locale = Localizations.localeOf(context).toString();
    final yearLabel = DateFormat.y(locale).format(DateTime(year.year));
    final allSelected =
        year.months.isNotEmpty &&
        year.months.every((month) => selectedMonths.contains(month.key));
    final completed = year.isCompleted;
    final collapsed = completed && !expanded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              yearLabel,
              style: TextStyles.display3.copyWith(color: colors.textBase),
            ),
            if (completed) ...[
              const SizedBox(width: Spacing.xs),
              SelectAllStatusIcon(
                isSelected: true,
                size: 16,
                tickIconSize: 12,
                tickStrokeWidth: 3.2,
                selectedFillColor: colors.primary,
                selectedTickColor: colors.specialWhite,
              ),
            ],
            const Spacer(),
            if (!collapsed)
              Semantics(
                button: true,
                selected: allSelected,
                label: l10n.selectYear(year: yearLabel),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onYearToggle,
                  child: SizedBox(
                    width: 28.182,
                    height: 28.182,
                    child: Center(
                      child: allSelected
                          ? const ReviewSelectedTick()
                          : HugeIcon(
                              icon: HugeIcons.strokeRoundedCircle,
                              size: 23.826,
                              strokeWidth: 2.11,
                              color: colors.textLighter,
                            ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: Spacing.xl),
        if (completed && year.months.length > 1)
          _AnimatedCompletedYear(
            year: year,
            yearLabel: yearLabel,
            selectedMonths: selectedMonths,
            expanded: expanded,
            onMonthTap: onMonthTap,
            onMonthLongPress: onMonthLongPress,
            onExpandedChanged: onExpandedChanged,
          )
        else if (collapsed)
          _CompletedYearRow(
            year: year,
            yearLabel: yearLabel,
            selected:
                year.months.length == 1 &&
                selectedMonths.contains(year.months.single.key),
            onTap: year.months.length == 1
                ? () => onMonthTap(year.months.single)
                : () => onExpandedChanged(true),
            onLongPress: year.months.length == 1
                ? () => onMonthLongPress(year.months.single)
                : null,
          )
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final perRow = _slotsPerRow(constraints.maxWidth);
              return Column(
                children: [
                  for (
                    var start = 0;
                    start < year.months.length;
                    start += perRow
                  ) ...[
                    if (start > 0) const SizedBox(height: _rowSpacing),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.sm,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (
                            var index = start;
                            index < start + perRow;
                            index++
                          )
                            index < year.months.length
                                ? _monthSlot(context, year.months[index], index)
                                : const SizedBox(width: _slotWidth),
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
          if (completed) ...[
            const SizedBox(height: Spacing.xl),
            _ReviewSeeLessButton(onTap: () => onExpandedChanged(false)),
          ],
        ],
      ],
    );
  }

  Widget _monthSlot(BuildContext context, ReviewMonthSummary month, int index) {
    final locale = Localizations.localeOf(context).toString();
    final label = DateFormat.MMM(locale).format(month.key.start);
    final tilt = month.state == ReviewMonthState.completed
        ? 0.0
        : (index.isEven ? _tiltDegrees : -_tiltDegrees) * math.pi / 180;
    return SizedBox(
      width: _slotWidth,
      height: _slotHeight,
      child: Center(
        child: Transform.rotate(
          angle: tilt,
          child: ReviewMonthCard(
            cover: month.cover,
            label: label,
            count: month.totalCount,
            state: month.state,
            progress: month.progress,
            selected: selectedMonths.contains(month.key),
            semanticLabel: DateFormat.yMMMM(locale).format(month.key.start),
            onTap: () => onMonthTap(month),
            onLongPress: () => onMonthLongPress(month),
          ),
        ),
      ),
    );
  }
}

class _AnimatedCompletedYear extends StatefulWidget {
  const _AnimatedCompletedYear({
    required this.year,
    required this.yearLabel,
    required this.selectedMonths,
    required this.expanded,
    required this.onMonthTap,
    required this.onMonthLongPress,
    required this.onExpandedChanged,
  });

  final ReviewYearSummary year;
  final String yearLabel;
  final Set<ReviewMonthKey> selectedMonths;
  final bool expanded;
  final ValueChanged<ReviewMonthSummary> onMonthTap;
  final ValueChanged<ReviewMonthSummary> onMonthLongPress;
  final ValueChanged<bool> onExpandedChanged;

  @override
  State<_AnimatedCompletedYear> createState() => _AnimatedCompletedYearState();
}

class _AnimatedCompletedYearState extends State<_AnimatedCompletedYear>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: Motion.slow + Motion.standard,
    value: widget.expanded ? 1 : 0,
  )..addStatusListener(_onAnimationStatus);
  late final _summaryOpacity = _animation.drive(
    Tween(
      begin: 1.0,
      end: 0.0,
    ).chain(CurveTween(curve: const Interval(0, 0.3))),
  );
  late final _footerOpacity = _animation.drive(
    CurveTween(curve: const Interval(0.7, 1)),
  );
  late bool _showAllCards = widget.expanded;
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _showAllCards = widget.expanded;
      _animation.value = widget.expanded ? 1 : 0;
    }
  }

  @override
  void didUpdateWidget(_AnimatedCompletedYear oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded == oldWidget.expanded) return;
    if (_reduceMotion) {
      _showAllCards = widget.expanded;
      _animation.value = widget.expanded ? 1 : 0;
    } else if (widget.expanded) {
      _showAllCards = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.expanded && !_reduceMotion) {
          _animation.forward();
        }
      });
    } else {
      _animation.reverse();
      if (_animation.isDismissed) _showAllCards = false;
    }
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (_reduceMotion ||
        (status != AnimationStatus.completed &&
            status != AnimationStatus.dismissed)) {
      return;
    }
    setState(() {
      _showAllCards = widget.expanded || status != AnimationStatus.dismissed;
    });
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final months = widget.year.months;
    final indices = [
      for (var index = 0; index < months.length; index++)
        if (_showAllCards || index < 2 || index == months.length - 1) index,
    ];
    final gridInteractive = widget.expanded && _animation.isCompleted;
    final collapsedInteractive = !widget.expanded && _animation.isDismissed;
    final summary = IgnorePointer(
      ignoring: !collapsedInteractive,
      child: ExcludeSemantics(
        excluding: !collapsedInteractive,
        child: FadeTransition(
          opacity: _summaryOpacity,
          child: _CompletedYearRow(
            year: widget.year,
            yearLabel: widget.yearLabel,
            selected: false,
            showCards: false,
            onTap: () => widget.onExpandedChanged(true),
          ),
        ),
      ),
    );
    final seeLess = IgnorePointer(
      ignoring: !gridInteractive,
      child: ExcludeSemantics(
        excluding: !gridInteractive,
        child: FadeTransition(
          opacity: _footerOpacity,
          child: _ReviewSeeLessButton(
            onTap: () => widget.onExpandedChanged(false),
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final perRow = ReviewYearSection._slotsPerRow(width);
        final rows = (months.length / perRow).ceil();
        final gap = perRow > 1
            ? (width - Spacing.sm * 2 - perRow * ReviewYearSection._slotWidth) /
                  (perRow - 1)
            : 0.0;
        final gridHeight =
            rows * ReviewYearSection._slotHeight +
            (rows - 1) * ReviewYearSection._rowSpacing;
        final footerHeight = math.max(
          24.0,
          MediaQuery.textScalerOf(context).scale(TextStyles.mini.fontSize!) *
              TextStyles.mini.height!,
        );
        final expandedHeight = gridHeight + Spacing.xl + footerHeight;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            _ReviewYearExtent(
              animation: _animation,
              expandedHeight: expandedHeight,
              child: summary,
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: math.max(142, expandedHeight),
              child: IgnorePointer(
                ignoring: !gridInteractive,
                child: ExcludeSemantics(
                  excluding: !gridInteractive,
                  child: Flow(
                    clipBehavior: Clip.none,
                    delegate: _ReviewMonthFlowDelegate(
                      animation: _animation,
                      indices: indices,
                      monthCount: months.length,
                      perRow: perRow,
                      gap: gap,
                    ),
                    children: [
                      for (final index in indices)
                        ReviewMonthCard(
                          key: ValueKey(months[index].key),
                          cover: months[index].cover,
                          label: DateFormat.MMM(
                            locale,
                          ).format(months[index].key.start),
                          count: months[index].totalCount,
                          state: months[index].state,
                          progress: months[index].progress,
                          selected: widget.selectedMonths.contains(
                            months[index].key,
                          ),
                          semanticLabel: DateFormat.yMMMM(
                            locale,
                          ).format(months[index].key.start),
                          onTap: () => widget.onMonthTap(months[index]),
                          onLongPress: () =>
                              widget.onMonthLongPress(months[index]),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: gridHeight + Spacing.xl,
              left: 0,
              right: 0,
              child: seeLess,
            ),
          ],
        );
      },
    );
  }
}

class _ReviewMonthFlowDelegate extends FlowDelegate {
  _ReviewMonthFlowDelegate({
    required this.animation,
    required this.indices,
    required this.monthCount,
    required this.perRow,
    required this.gap,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final List<int> indices;
  final int monthCount;
  final int perRow;
  final double gap;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      const BoxConstraints.tightFor(
        width: ReviewMonthCard.width,
        height: ReviewMonthCard.height,
      );

  @override
  void paintChildren(FlowPaintingContext context) {
    for (var childIndex = indices.length - 1; childIndex >= 0; childIndex--) {
      final index = indices[childIndex];
      final delay = 0.2 * index / (monthCount - 1);
      final progress = ((animation.value - delay) / 0.8).clamp(0.0, 1.0);
      final eased = Curves.easeInOutCubic.transform(progress);
      final opacity = index < 2 || index == monthCount - 1 ? 1.0 : eased;
      if (opacity == 0) continue;
      final (stackPosition, stackDegrees) = switch (index) {
        0 => (const Offset(47.732, 11.437), 0.0),
        1 => (const Offset(25.389, 5.44), -7.06),
        _ => (const Offset(1.754, -0.16), -14.19),
      };
      final gridPosition = Offset(
        Spacing.sm +
            (index % perRow) * (ReviewYearSection._slotWidth + gap) +
            (ReviewYearSection._slotWidth - ReviewMonthCard.width) / 2,
        (index ~/ perRow) *
                (ReviewYearSection._slotHeight +
                    ReviewYearSection._rowSpacing) +
            (ReviewYearSection._slotHeight - ReviewMonthCard.height) / 2,
      );
      final shuffle = math.sin(eased * math.pi);
      final position =
          Offset.lerp(
            stackPosition + const Offset(Spacing.sm, 0),
            gridPosition,
            eased,
          )! -
          Offset(0, Spacing.sm * shuffle);
      final degrees =
          stackDegrees * (1 - eased) + (index.isEven ? 6 : -6) * shuffle;
      context.paintChild(
        childIndex,
        transform: Matrix4.identity()
          ..translateByDouble(
            position.dx + ReviewMonthCard.width / 2,
            position.dy + ReviewMonthCard.height / 2,
            0,
            1,
          )
          ..rotateZ(degrees * math.pi / 180)
          ..translateByDouble(
            -ReviewMonthCard.width / 2,
            -ReviewMonthCard.height / 2,
            0,
            1,
          ),
        opacity: opacity,
      );
    }
  }

  @override
  bool shouldRepaint(_ReviewMonthFlowDelegate oldDelegate) =>
      oldDelegate.animation != animation ||
      oldDelegate.monthCount != monthCount ||
      oldDelegate.indices.length != indices.length ||
      oldDelegate.perRow != perRow ||
      oldDelegate.gap != gap;
}

class _ReviewYearExtent extends SingleChildRenderObjectWidget {
  const _ReviewYearExtent({
    required this.animation,
    required this.expandedHeight,
    required super.child,
  });

  final Animation<double> animation;
  final double expandedHeight;

  @override
  _RenderReviewYearExtent createRenderObject(BuildContext context) =>
      _RenderReviewYearExtent(animation, expandedHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderReviewYearExtent renderObject,
  ) {
    renderObject
      ..animation = animation
      ..expandedHeight = expandedHeight;
  }
}

class _RenderReviewYearExtent extends RenderProxyBox {
  _RenderReviewYearExtent(this._animation, this._expandedHeight);

  Animation<double> _animation;
  double _expandedHeight;

  set animation(Animation<double> value) {
    if (_animation == value) return;
    if (attached) _animation.removeListener(markNeedsLayout);
    _animation = value;
    if (attached) _animation.addListener(markNeedsLayout);
    markNeedsLayout();
  }

  set expandedHeight(double value) {
    if (_expandedHeight == value) return;
    _expandedHeight = value;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _animation.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _animation.removeListener(markNeedsLayout);
    super.detach();
  }

  BoxConstraints get _summaryConstraints =>
      constraints.copyWith(minHeight: 0, maxHeight: double.infinity);

  Size _sizeFor(BoxConstraints constraints, Size summarySize) {
    final progress = Curves.easeInOutCubic.transform(_animation.value);
    return constraints.constrain(
      Size(
        summarySize.width,
        summarySize.height + (_expandedHeight - summarySize.height) * progress,
      ),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => _sizeFor(
    constraints,
    child!.getDryLayout(
      constraints.copyWith(minHeight: 0, maxHeight: double.infinity),
    ),
  );

  @override
  void performLayout() {
    child!.layout(_summaryConstraints, parentUsesSize: true);
    size = _sizeFor(constraints, child!.size);
  }
}

class _ReviewSeeLessButton extends StatelessWidget {
  const _ReviewSeeLessButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Center(
      child: Semantics(
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.strings.seeLess,
                style: TextStyles.mini.copyWith(color: colors.textLight),
              ),
              const SizedBox(width: Spacing.xs),
              SizedBox(
                width: 12,
                height: 24,
                child: Center(
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowUp01,
                    size: IconSizes.tiny,
                    strokeWidth: 3,
                    color: colors.textLight,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompletedYearRow extends StatelessWidget {
  const _CompletedYearRow({
    required this.year,
    required this.yearLabel,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.showCards = true,
  });

  final ReviewYearSummary year;
  final String yearLabel;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool showCards;

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;
    final colors = context.componentColors;
    final locale = Localizations.localeOf(context).toString();
    final months = year.months;
    final stacked = [
      if (months.length > 2) (months.last, -14.19, const Offset(1.754, -0.16)),
      if (months.length > 1) (months[1], -7.06, const Offset(25.389, 5.44)),
      (months[0], 0.0, const Offset(47.732, 11.437)),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
      child: Row(
        crossAxisAlignment: showCards
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            selected: months.length == 1 ? selected : null,
            label: months.length == 1
                ? DateFormat.yMMMM(locale).format(months.single.key.start)
                : l10n.seeAll,
            excludeSemantics: true,
            onTap: onTap,
            onLongPress: onLongPress,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: onTap,
              onLongPress: onLongPress,
              child: SizedBox(
                width: 134,
                height: 142,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (showCards)
                      for (final (month, degrees, offset) in stacked)
                        Positioned(
                          left: offset.dx,
                          top: offset.dy,
                          child: Transform.rotate(
                            angle: degrees * math.pi / 180,
                            child: ReviewMonthCard(
                              cover: month.cover,
                              label: DateFormat.MMM(
                                locale,
                              ).format(month.key.start),
                              count: month.totalCount,
                              state: ReviewMonthState.completed,
                              progress: 1,
                              selected: selected,
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 25),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 142),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.reviewYouReviewedYear(year: yearLabel),
                      textAlign: TextAlign.center,
                      style: TextStyles.display3.copyWith(
                        fontSize: 18,
                        height: null,
                        color: colors.textBase,
                      ),
                    ),
                    if (months.length > 1) ...[
                      const SizedBox(height: Spacing.sm),
                      ChipSurface(
                        surfaceKey: ValueKey("review-see-all-${year.year}"),
                        enabled: true,
                        selected: false,
                        semanticLabel: l10n.seeAll,
                        minHeight: 36,
                        minWidth: 99,
                        padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.xxl,
                        ),
                        background: colors.fillLight,
                        borderRadius: BorderRadius.circular(Radii.md),
                        onTap: onTap,
                        child: Text(
                          l10n.seeAll,
                          style: TextStyles.display3.copyWith(
                            fontSize: 10,
                            height: 28 / 10,
                            color: colors.textBase,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
