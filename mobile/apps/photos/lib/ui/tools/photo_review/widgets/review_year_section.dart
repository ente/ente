import "dart:math" as math;

import "package:ente_components/components/chip_surface.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:intl/intl.dart" show DateFormat;
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
  static const double _yearToggleSize = 28.182;
  static const double _completedTickSize = 16;
  static const double _summaryCardWidth = 134;
  static const double _summaryMinHeight = 142;
  static const double _summaryGap = 25;
  static const double _seeAllMinHeight = 36;
  static const double _footerMinHeight = 24;
  static final _summaryTextStyle = TextStyles.display3.copyWith(fontSize: 18);
  static final _seeAllTextStyle = TextStyles.display3.copyWith(
    fontSize: 10,
    height: 28 / 10,
  );

  static int _slotsPerRow(double width) {
    final usable = width - Spacing.sm * 2 + _minSlotGap;
    return math.max(1, (usable / (_slotWidth + _minSlotGap)).floor());
  }

  static double _slotGap(double width, int perRow) => perRow > 1
      ? (width - Spacing.sm * 2 - perRow * _slotWidth) / (perRow - 1)
      : _minSlotGap;

  static double heightFor(
    BuildContext context, {
    required ReviewYearSummary year,
    required bool expanded,
    required double width,
  }) {
    final locale = Localizations.localeOf(context).toString();
    final yearLabel = DateFormat.y(locale).format(DateTime(year.year));
    final completed = year.isCompleted;
    final collapsed = completed && !expanded;
    final headerHeight = math.max(
      _textHeight(context, yearLabel, TextStyles.display3),
      collapsed ? _completedTickSize : _yearToggleSize,
    );
    final double bodyHeight;
    if (collapsed) {
      bodyHeight = _summaryHeight(
        context,
        yearLabel,
        year.months.length,
        width,
      );
    } else {
      bodyHeight =
          _gridHeightFor(year.months.length, width) +
          (completed
              ? Spacing.xl +
                    (year.months.length > 1
                        ? _animatedFooterHeightFor(context)
                        : math.max(
                            _footerMinHeight,
                            _textHeight(
                              context,
                              context.strings.seeLess,
                              TextStyles.mini,
                            ),
                          ))
              : 0);
    }
    return headerHeight + Spacing.xl + bodyHeight;
  }

  static double _summaryHeight(
    BuildContext context,
    String yearLabel,
    int monthCount,
    double width,
  ) {
    final textWidth = math.max(
      0.0,
      width - Spacing.sm * 2 - _summaryCardWidth - _summaryGap,
    );
    var height = _textHeight(
      context,
      context.strings.reviewYouReviewedYear(year: yearLabel),
      _summaryTextStyle,
      maxWidth: textWidth,
      textAlign: TextAlign.center,
    );
    if (monthCount > 1) {
      height +=
          Spacing.sm +
          math.max(
            _seeAllMinHeight,
            _textHeight(
              context,
              context.strings.seeAll,
              _seeAllTextStyle,
              maxWidth: math.max(0.0, textWidth - Spacing.xxl * 2),
            ),
          );
    }
    return math.max(_summaryMinHeight, height);
  }

  static double _gridHeightFor(int count, double width) {
    final rows = (count / _slotsPerRow(width)).ceil();
    return rows * _slotHeight + (rows - 1) * _rowSpacing;
  }

  static double _animatedFooterHeightFor(BuildContext context) => math.max(
    _footerMinHeight,
    MediaQuery.textScalerOf(context).scale(TextStyles.mini.fontSize!) *
        TextStyles.mini.height!,
  );

  static double _textHeight(
    BuildContext context,
    String text,
    TextStyle style, {
    double maxWidth = double.infinity,
    TextAlign? textAlign,
  }) {
    final defaults = DefaultTextStyle.of(context);
    var effectiveStyle = defaults.style.merge(style);
    if (MediaQuery.boldTextOf(context)) {
      effectiveStyle = effectiveStyle.merge(
        const TextStyle(fontWeight: FontWeight.bold),
      );
    }
    effectiveStyle = effectiveStyle.merge(
      TextStyle(
        height: MediaQuery.maybeLineHeightScaleFactorOverrideOf(context),
        letterSpacing: MediaQuery.maybeLetterSpacingOverrideOf(context),
        wordSpacing: MediaQuery.maybeWordSpacingOverrideOf(context),
      ),
    );
    final overflow = effectiveStyle.overflow ?? defaults.overflow;
    final painter =
        TextPainter(
          text: TextSpan(text: text, style: effectiveStyle),
          textAlign: textAlign ?? defaults.textAlign ?? TextAlign.start,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
          maxLines: defaults.maxLines,
          textWidthBasis: defaults.textWidthBasis,
          textHeightBehavior:
              defaults.textHeightBehavior ??
              DefaultTextHeightBehavior.maybeOf(context),
          ellipsis: overflow == TextOverflow.ellipsis ? "\u2026" : null,
        )..layout(
          maxWidth: defaults.softWrap || overflow == TextOverflow.ellipsis
              ? maxWidth
              : double.infinity,
        );
    final height = painter.height;
    painter.dispose();
    return height;
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
                size: _completedTickSize,
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
                    width: _yearToggleSize,
                    height: _yearToggleSize,
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
            expanded: expanded,
            cardBuilder: (_, index) => _monthCard(year.months[index], locale),
            onExpandedChanged: onExpandedChanged,
          )
        else if (collapsed)
          _CompletedYearRow(
            year: year,
            yearLabel: yearLabel,
            selected: selectedMonths.contains(year.months.single.key),
            onTap: () => onMonthTap(year.months.single),
            onLongPress: () => onMonthLongPress(year.months.single),
          )
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final perRow = _slotsPerRow(constraints.maxWidth);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
                child: Wrap(
                  spacing: _slotGap(constraints.maxWidth, perRow),
                  runSpacing: _rowSpacing,
                  children: [
                    for (var index = 0; index < year.months.length; index++)
                      _monthSlot(year.months[index], index, locale),
                  ],
                ),
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

  Widget _monthSlot(ReviewMonthSummary month, int index, String locale) {
    final tilt = month.state == ReviewMonthState.completed
        ? 0.0
        : (index.isEven ? _tiltDegrees : -_tiltDegrees) * math.pi / 180;
    return SizedBox(
      width: _slotWidth,
      height: _slotHeight,
      child: Center(
        child: Transform.rotate(angle: tilt, child: _monthCard(month, locale)),
      ),
    );
  }

  Widget _monthCard(ReviewMonthSummary month, String locale) {
    return ReviewMonthCard(
      key: ValueKey(month.key),
      cover: month.cover,
      label: DateFormat.MMM(locale).format(month.key.start),
      count: month.totalCount,
      state: month.state,
      progress: month.progress,
      selected: selectedMonths.contains(month.key),
      semanticLabel: DateFormat.yMMMM(locale).format(month.key.start),
      onTap: () => onMonthTap(month),
      onLongPress: () => onMonthLongPress(month),
    );
  }
}

class _AnimatedCompletedYear extends StatefulWidget {
  const _AnimatedCompletedYear({
    required this.year,
    required this.yearLabel,
    required this.expanded,
    required this.cardBuilder,
    required this.onExpandedChanged,
  });

  final ReviewYearSummary year;
  final String yearLabel;
  final bool expanded;
  final IndexedWidgetBuilder cardBuilder;
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
  late final _summaryOpacity = ReverseAnimation(
    _animation.drive(CurveTween(curve: const Interval(0, 0.3))),
  );
  late final _footerOpacity = _animation.drive(
    CurveTween(curve: const Interval(0.7, 1)),
  );
  bool _reduceMotion = false;
  ScrollNotificationObserverState? _scrollObserver;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final observer = ScrollNotificationObserver.maybeOf(context);
    if (!identical(observer, _scrollObserver)) {
      _scrollObserver?.removeListener(_onScrollNotification);
      _scrollObserver = observer;
      _scrollObserver?.addListener(_onScrollNotification);
    }
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion) {
      _animation.value = widget.expanded ? 1 : 0;
    }
  }

  @override
  void didUpdateWidget(_AnimatedCompletedYear oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded == oldWidget.expanded) return;
    if (_reduceMotion) {
      _animation.value = widget.expanded ? 1 : 0;
    } else if (widget.expanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.expanded && !_reduceMotion) {
          _animation.forward();
        }
      });
    } else {
      _animation.reverse();
    }
  }

  void _onAnimationStatus(AnimationStatus status) {
    if (_reduceMotion ||
        (status != AnimationStatus.completed &&
            status != AnimationStatus.dismissed)) {
      return;
    }
    setState(() {});
  }

  void _onScrollNotification(ScrollNotification notification) {
    if (notification is! ScrollStartNotification ||
        notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical) {
      return;
    }
    final target = widget.expanded ? 1.0 : 0.0;
    if (_animation.value != target) _animation.value = target;
  }

  @override
  void dispose() {
    _scrollObserver?.removeListener(_onScrollNotification);
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final months = widget.year.months;
    final showAllCards = widget.expanded || !_animation.isDismissed;
    final indices = [
      for (var index = 0; index < months.length; index++)
        if (showAllCards || index < 2 || index == months.length - 1) index,
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
        final gap = ReviewYearSection._slotGap(width, perRow);
        final gridHeight = ReviewYearSection._gridHeightFor(
          months.length,
          width,
        );
        final footerHeight = ReviewYearSection._animatedFooterHeightFor(
          context,
        );
        final expandedHeight = gridHeight + Spacing.xl + footerHeight;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            CustomSingleChildLayout(
              delegate: _ReviewYearLayout(
                _animation,
                ReviewYearSection._summaryHeight(
                  context,
                  widget.yearLabel,
                  months.length,
                  width,
                ),
                expandedHeight,
              ),
              child: summary,
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: math.max(
                ReviewYearSection._summaryMinHeight,
                expandedHeight,
              ),
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
                      textDirection: Directionality.of(context),
                    ),
                    children: [
                      for (final index in indices)
                        widget.cardBuilder(context, index),
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
    required this.textDirection,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final List<int> indices;
  final int monthCount;
  final int perRow;
  final double gap;
  final TextDirection textDirection;

  @override
  BoxConstraints getConstraintsForChild(int i, BoxConstraints constraints) =>
      const BoxConstraints.tightFor(
        width: ReviewMonthCard.width,
        height: ReviewMonthCard.height,
      );

  @override
  void paintChildren(FlowPaintingContext context) {
    final rtl = textDirection == TextDirection.rtl;
    final stackLeft = rtl
        ? context.size.width - Spacing.sm - ReviewYearSection._summaryCardWidth
        : Spacing.sm;
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
      final gridLeft =
          Spacing.sm +
          (index % perRow) * (ReviewYearSection._slotWidth + gap) +
          (ReviewYearSection._slotWidth - ReviewMonthCard.width) / 2;
      final gridPosition = Offset(
        rtl ? context.size.width - gridLeft - ReviewMonthCard.width : gridLeft,
        (index ~/ perRow) *
                (ReviewYearSection._slotHeight +
                    ReviewYearSection._rowSpacing) +
            (ReviewYearSection._slotHeight - ReviewMonthCard.height) / 2,
      );
      final shuffle = math.sin(eased * math.pi);
      final position =
          Offset.lerp(
            Offset(stackLeft + stackPosition.dx, stackPosition.dy),
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
      oldDelegate.gap != gap ||
      oldDelegate.textDirection != textDirection;
}

class _ReviewYearLayout extends SingleChildLayoutDelegate {
  _ReviewYearLayout(this.animation, this.collapsedHeight, this.expandedHeight)
    : super(relayout: animation);

  final Animation<double> animation;
  final double collapsedHeight;
  final double expandedHeight;

  @override
  Size getSize(BoxConstraints constraints) => constraints.constrain(
    Size(
      constraints.maxWidth,
      collapsedHeight +
          (expandedHeight - collapsedHeight) *
              Curves.easeInOutCubic.transform(animation.value),
    ),
  );

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.copyWith(minHeight: 0, maxHeight: double.infinity);

  @override
  bool shouldRelayout(_ReviewYearLayout oldDelegate) =>
      oldDelegate.animation != animation ||
      oldDelegate.collapsedHeight != collapsedHeight ||
      oldDelegate.expandedHeight != expandedHeight;
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
                height: ReviewYearSection._footerMinHeight,
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
                width: ReviewYearSection._summaryCardWidth,
                height: ReviewYearSection._summaryMinHeight,
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
          const SizedBox(width: ReviewYearSection._summaryGap),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: ReviewYearSection._summaryMinHeight,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.reviewYouReviewedYear(year: yearLabel),
                      textAlign: TextAlign.center,
                      style: ReviewYearSection._summaryTextStyle.copyWith(
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
                        minHeight: ReviewYearSection._seeAllMinHeight,
                        minWidth: 99,
                        padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.xxl,
                        ),
                        background: colors.fillLight,
                        borderRadius: BorderRadius.circular(Radii.md),
                        onTap: onTap,
                        child: Text(
                          l10n.seeAll,
                          style: ReviewYearSection._seeAllTextStyle.copyWith(
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
