import "dart:math" as math;

import "package:ente_components/components/chip_surface.dart";
import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:hugeicons/hugeicons.dart";
import "package:intl/intl.dart";
import "package:photos/models/photo_review/photo_review_models.dart";
import "package:photos/ui/tools/photo_review/widgets/review_month_card.dart";

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
              SvgPicture.asset(
                ReviewMonthCard.sparkleAsset,
                width: 7,
                height: 7,
                colorFilter: ColorFilter.mode(colors.primary, BlendMode.srcIn),
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
        if (collapsed)
          _CompletedYearRow(
            year: year,
            yearLabel: yearLabel,
            onSeeAll: () => onExpandedChanged(true),
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
            Center(
              child: Semantics(
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onExpandedChanged(false),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l10n.seeLess,
                        style: TextStyles.mini.copyWith(
                          color: colors.textLight,
                        ),
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
            ),
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

class _CompletedYearRow extends StatelessWidget {
  const _CompletedYearRow({
    required this.year,
    required this.yearLabel,
    required this.onSeeAll,
  });

  final ReviewYearSummary year;
  final String yearLabel;
  final VoidCallback onSeeAll;

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
        children: [
          SizedBox(
            width: 134,
            height: 142,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final (month, degrees, offset) in stacked)
                  Positioned(
                    left: offset.dx,
                    top: offset.dy,
                    child: Transform.rotate(
                      angle: degrees * math.pi / 180,
                      child: ReviewMonthCard(
                        cover: month.cover,
                        label: DateFormat.MMM(locale).format(month.key.start),
                        count: month.totalCount,
                        state: ReviewMonthState.completed,
                        progress: 1,
                        selected: false,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 25),
          Expanded(
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
                const SizedBox(height: Spacing.sm),
                ChipSurface(
                  surfaceKey: ValueKey("review-see-all-${year.year}"),
                  enabled: true,
                  selected: false,
                  semanticLabel: l10n.seeAll,
                  minHeight: 36,
                  minWidth: 99,
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.xxl),
                  background: colors.fillLight,
                  borderRadius: BorderRadius.circular(Radii.md),
                  onTap: onSeeAll,
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
            ),
          ),
        ],
      ),
    );
  }
}
