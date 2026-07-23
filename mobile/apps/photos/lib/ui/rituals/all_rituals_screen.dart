import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_icons/ente_icons.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/rituals/ritual_models.dart";
import "package:photos/service_locator.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/rituals/delete_ritual_confirmation_sheet.dart";
import "package:photos/ui/rituals/ritual_camera_page.dart";
import "package:photos/ui/rituals/ritual_day_thumbnail.dart";
import "package:photos/ui/rituals/ritual_editor_dialog.dart";
import "package:photos/ui/rituals/ritual_emoji_icon.dart";
import "package:photos/ui/rituals/ritual_page.dart";
import "package:photos/ui/rituals/ritual_privacy.dart";
import "package:photos/ui/rituals/start_new_ritual_card.dart";

class AllRitualsScreen extends StatelessWidget {
  const AllRitualsScreen({super.key, this.ritual});

  // Legacy param; retained for call sites that pass it.
  final Ritual? ritual;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final ritualsEnabled = flagService.ritualsFlag;
    if (!ritualsEnabled) {
      return Scaffold(
        body: AppBarComponent(
          title: l10n.ritualsTitle,
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    "Rituals are currently limited to internal users.",
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Scaffold(
      body: ValueListenableBuilder<RitualsState>(
        valueListenable: ritualsService.stateNotifier,
        builder: (context, state, _) {
          final rituals = state.rituals;
          final summary = state.summary;
          return AppBarComponent(
            title: l10n.ritualsTitle,
            physics: const BouncingScrollPhysics(),
            actions: [
              IconButtonComponent(
                variant: IconButtonComponentVariant.green,
                shouldSurfaceExecutionStates: false,
                icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedPlusSign,
                  size: 24,
                  color: Colors.white,
                ),
                onTap: () async {
                  await showRitualEditor(context, ritual: null);
                },
                tooltip: l10n.ritualAddTooltip,
              ),
            ],
            slivers: [
              SliverSafeArea(
                top: false,
                sliver: SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
                  sliver: rituals.isEmpty
                      ? SliverToBoxAdapter(
                          child: StartNewRitualCard(
                            variant: StartNewRitualCardVariant.wide,
                            onTap: () async {
                              await showRitualEditor(context, ritual: null);
                            },
                          ),
                        )
                      : SliverList(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final ritual = rituals[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _RitualOverviewCard(
                                ritual: ritual,
                                progress: summary?.ritualProgress[ritual.id],
                              ),
                            );
                          }, childCount: rituals.length),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RitualOverviewCard extends StatelessWidget {
  const _RitualOverviewCard({required this.ritual, required this.progress});

  final Ritual ritual;
  final RitualProgress? progress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final preview = _ritualPreviewDays(
      ritual: ritual,
      progress: progress,
      todayMidnight: today,
      count: 5,
    );
    final days = preview.days;
    final showFuturePreview = preview.showFuturePreview;
    final completions = [
      for (final day in days) progress?.hasCompleted(day) ?? false,
    ];
    final isHiddenRitual = isRitualAlbumHidden(ritual);

    return GestureDetector(
      onTap: () async {
        final canOpen = await requestHiddenRitualAccess(context, ritual);
        if (!context.mounted || !canOpen) return;
        unawaited(routeToPage(context, RitualPage(ritualId: ritual.id)));
      },
      onLongPress: () async {
        final action = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: Colors.transparent,
          builder: (context) => _RitualActionsSheet(ritual: ritual),
        );
        switch (action) {
          case "edit":
            if (!context.mounted) return;
            await showRitualEditor(context, ritual: ritual);
            break;
          case "delete":
            if (!context.mounted) return;
            final confirmed = await showDeleteRitualConfirmationSheet(context);
            if (!context.mounted || !confirmed) return;
            await ritualsService.deleteRitual(ritual.id);
            break;
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).brightness == Brightness.dark
              ? colorScheme.backgroundElevated2
              : const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? colorScheme.strokeFaint
                : Colors.black.withValues(alpha: 0.04),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: colorScheme.backgroundElevated,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: RitualEmojiIcon(
                      ritual.icon,
                      style: textTheme.bodyBold.copyWith(height: 1),
                      textHeightBehavior: _tightTextHeightBehavior,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ritual.title.isEmpty
                        ? context.l10n.ritualUntitled
                        : ritual.title,
                    style: textTheme.bodyBold,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textHeightBehavior: _tightTextHeightBehavior,
                  ),
                ),
                const SizedBox(width: 8),
                _StreakChip(streak: progress?.currentStreak ?? 0),
              ],
            ),
            const SizedBox(height: 16),
            if (days.isNotEmpty)
              LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 16.0;
                  final available =
                      constraints.maxWidth - (spacing * (days.length - 1));
                  final tileWidth = available / days.length;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final (index, day) in days.indexed) ...[
                        if (index != 0) const SizedBox(width: spacing),
                        Expanded(
                          child: Align(
                            alignment: Alignment.center,
                            child: _buildDayThumbnail(
                              context: context,
                              ritual: ritual,
                              day: day,
                              tileWidth: tileWidth,
                              completed: completions[index],
                              nextCompleted: index == days.length - 1
                                  ? null
                                  : completions[index + 1],
                              index: index,
                              showFuturePreview: showFuturePreview,
                              isHiddenRitual: isHiddenRitual,
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayThumbnail({
    required BuildContext context,
    required Ritual ritual,
    required DateTime day,
    required double tileWidth,
    required bool completed,
    required bool? nextCompleted,
    required int index,
    required bool showFuturePreview,
    required bool isHiddenRitual,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dayKey = DateTime(
      day.year,
      day.month,
      day.day,
    ).millisecondsSinceEpoch;
    final file = progress?.recentFilesByDay[dayKey];
    final count =
        progress?.recentFileCountsByDay[dayKey] ?? (completed ? 1 : 0);
    final isToday = _isSameDay(day, today);
    final isYesterday = _isSameDay(day, yesterday);
    final shouldShowCamera =
        isToday && !completed && file == null && count == 0;
    final shouldHidePhoto =
        isHiddenRitual && !shouldShowCamera && !day.isAfter(today);
    final fadePhoto =
        completed && nextCompleted == false && !isYesterday && !isToday;
    final rotation = switch (index % 4) {
      0 => -0.05,
      1 => 0.10,
      2 => -0.08,
      _ => 0.08,
    };

    if (shouldHidePhoto) {
      return RitualDayThumbnail(
        day: day,
        variant: RitualDayThumbnailVariant.hidden,
        width: tileWidth,
      );
    }

    final variant = completed
        ? RitualDayThumbnailVariant.photo
        : (isToday
              ? RitualDayThumbnailVariant.camera
              : (showFuturePreview && day.isAfter(today)
                    ? RitualDayThumbnailVariant.future
                    : RitualDayThumbnailVariant.empty));

    return RitualDayThumbnail(
      day: day,
      variant: variant,
      width: tileWidth,
      photoFile: file,
      photoCount: count,
      fadePhoto: fadePhoto,
      rotation: rotation,
      onCameraTap: isToday && !completed
          ? () => openRitualCamera(context, ritual)
          : null,
    );
  }
}

class _StreakChip extends StatelessWidget {
  const _StreakChip({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.backgroundElevated,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "$streak",
            style: textTheme.small.copyWith(
              color: colorScheme.textMuted,
              height: 1,
            ),
            textHeightBehavior: _tightTextHeightBehavior,
          ),
          const SizedBox(width: 4),
          const Icon(
            EnteIcons.lightningFilled,
            size: 14,
            color: Color(0xFFFFBC03),
          ),
        ],
      ),
    );
  }
}

class _RitualActionsSheet extends StatelessWidget {
  const _RitualActionsSheet({required this.ritual});

  final Ritual ritual;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.backgroundElevated,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colorScheme.strokeFaint, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(context.l10n.edit, style: textTheme.body),
                leading: HugeIcon(
                  icon: HugeIcons.strokeRoundedPencilEdit01,
                  color: colorScheme.textBase,
                  size: 22,
                ),
                onTap: () => Navigator.of(context).pop("edit"),
              ),
              Divider(
                height: 0.5,
                thickness: 0.5,
                color: colorScheme.strokeFaint,
              ),
              ListTile(
                title: Text(
                  context.l10n.delete,
                  style: textTheme.body.copyWith(color: Colors.red),
                ),
                leading: const HugeIcon(
                  icon: HugeIcons.strokeRoundedDelete02,
                  color: Colors.red,
                  size: 22,
                ),
                onTap: () => Navigator.of(context).pop("delete"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

List<DateTime> _lastScheduledDaysInclusive({
  required Ritual ritual,
  required DateTime todayMidnight,
  required int count,
}) {
  final daysOfWeek = ritual.daysOfWeek;
  if (daysOfWeek.length != 7) return const [];

  final result = <DateTime>[];
  for (int offset = 0; result.length < count && offset < 366; offset++) {
    final day = todayMidnight.subtract(Duration(days: offset));
    final weekdayIndex = day.weekday % 7; // Sunday-first
    if (!_isScheduledDay(daysOfWeek, weekdayIndex)) continue;
    result.add(day);
  }
  return result.reversed.toList(growable: false);
}

List<DateTime> _nextScheduledDaysInclusive({
  required Ritual ritual,
  required DateTime todayMidnight,
  required int count,
}) {
  final daysOfWeek = ritual.daysOfWeek;
  if (daysOfWeek.length != 7) return const [];

  final result = <DateTime>[];
  for (int offset = 0; result.length < count && offset < 366; offset++) {
    final day = todayMidnight.add(Duration(days: offset));
    final weekdayIndex = day.weekday % 7; // Sunday-first
    if (!_isScheduledDay(daysOfWeek, weekdayIndex)) continue;
    result.add(day);
  }
  return result.toList(growable: false);
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

({List<DateTime> days, bool showFuturePreview}) _ritualPreviewDays({
  required Ritual ritual,
  required RitualProgress? progress,
  required DateTime todayMidnight,
  required int count,
}) {
  final pastDays = _lastScheduledDaysInclusive(
    ritual: ritual,
    todayMidnight: todayMidnight,
    count: count,
  );
  final todayScheduled = pastDays.any((day) => _isSameDay(day, todayMidnight));

  if (progress == null || count <= 1) {
    return (days: pastDays, showFuturePreview: false);
  }

  final createdAt = ritual.createdAt.toLocal();
  final createdDayMidnight = DateTime(
    createdAt.year,
    createdAt.month,
    createdAt.day,
  );

  final lookbackCount = count - 1;
  final daysBeforeCreation = _lastScheduledDaysInclusive(
    ritual: ritual,
    todayMidnight: createdDayMidnight.subtract(const Duration(days: 1)),
    count: lookbackCount,
  );
  final hadCompletionsBeforeCreation = daysBeforeCreation.any(
    progress.hasCompleted,
  );
  if (hadCompletionsBeforeCreation) {
    return (days: pastDays, showFuturePreview: false);
  }

  final maxShift = count - 1;
  final shiftSlots = _scheduledSlotsSinceCreation(
    ritual: ritual,
    createdDayMidnight: createdDayMidnight,
    todayMidnight: todayMidnight,
    maxSlots: maxShift,
  );
  if (shiftSlots >= maxShift) {
    return (days: pastDays, showFuturePreview: false);
  }

  final shiftedPast = todayScheduled
      ? _lastScheduledDaysInclusive(
          ritual: ritual,
          todayMidnight: todayMidnight,
          count: shiftSlots + 1,
        )
      : _lastScheduledDaysInclusive(
          ritual: ritual,
          todayMidnight: todayMidnight,
          count: shiftSlots,
        );
  final shiftedFuture = _nextScheduledDaysInclusive(
    ritual: ritual,
    todayMidnight: todayMidnight,
    count: count - shiftSlots,
  );
  final days = [
    ...shiftedPast,
    ...(todayScheduled ? shiftedFuture.skip(1) : shiftedFuture),
  ];
  return (days: days, showFuturePreview: true);
}

int _scheduledSlotsSinceCreation({
  required Ritual ritual,
  required DateTime createdDayMidnight,
  required DateTime todayMidnight,
  required int maxSlots,
}) {
  if (maxSlots <= 0) return 0;
  if (todayMidnight.isBefore(createdDayMidnight)) return 0;

  final daysOfWeek = ritual.daysOfWeek;
  if (daysOfWeek.length != 7) return 0;

  int slots = 0;
  for (int offset = 1; slots < maxSlots && offset < 366; offset++) {
    final day = todayMidnight.subtract(Duration(days: offset));
    if (day.isBefore(createdDayMidnight)) break;
    final weekdayIndex = day.weekday % 7; // Sunday-first
    if (!_isScheduledDay(daysOfWeek, weekdayIndex)) continue;
    slots += 1;
  }
  return slots;
}

bool _hasAnyEnabledRitualDays(List<bool> daysOfWeek) {
  if (daysOfWeek.length != 7) return false;
  for (final enabled in daysOfWeek) {
    if (enabled) return true;
  }
  return false;
}

bool _isScheduledDay(List<bool> daysOfWeek, int dayIndex) {
  if (daysOfWeek.length != 7) return false;
  if (!_hasAnyEnabledRitualDays(daysOfWeek)) return true;
  return daysOfWeek[dayIndex];
}

const _tightTextHeightBehavior = TextHeightBehavior(
  applyHeightToFirstAscent: false,
  applyHeightToLastDescent: false,
);
