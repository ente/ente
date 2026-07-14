import "dart:io";
import "dart:math" as math;
import "dart:ui" as ui;

import "package:ente_icons/ente_icons.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:hugeicons/hugeicons.dart";
import "package:intl/intl.dart";
import "package:logging/logging.dart";
import "package:path_provider/path_provider.dart";
import "package:photos/db/files_db.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/collection/collection_items.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/rituals/ritual_models.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/rituals/delete_ritual_confirmation_sheet.dart";
import "package:photos/ui/rituals/ritual_camera_page.dart";
import "package:photos/ui/rituals/ritual_day_thumbnail.dart";
import "package:photos/ui/rituals/ritual_editor_dialog.dart";
import "package:photos/ui/rituals/ritual_emoji_icon.dart";
import "package:photos/ui/rituals/ritual_share_card.dart";
import "package:photos/ui/viewer/file/detail_page.dart";
import "package:photos/ui/viewer/gallery/collection_page.dart";
import "package:photos/utils/share_util.dart";
import "package:share_plus/share_plus.dart";

class RitualPage extends StatefulWidget {
  const RitualPage({super.key, required this.ritualId});

  final String ritualId;

  @override
  State<RitualPage> createState() => _RitualPageState();
}

class _RitualPageState extends State<RitualPage> {
  static final Logger _logger = Logger("RitualPage");

  late DateTime _visibleMonth;
  final GlobalKey _shareButtonKey = GlobalKey();
  bool _sharing = false;

  Future<void> _confirmAndDeleteRitual(Ritual ritual) async {
    final shouldDelete = await showDeleteRitualConfirmationSheet(context);
    if (!shouldDelete) return;

    try {
      await ritualsService.deleteRitual(ritual.id);
    } catch (e, s) {
      _logger.warning("Failed to delete ritual", e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.somethingWentWrongPleaseTryAgain),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).maybePop();
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
  }

  void _goToPreviousMonth() {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
    });
  }

  void _goToNextMonth() {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final nextMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
    if (!nextMonth.isAfter(currentMonth)) {
      setState(() {
        _visibleMonth = nextMonth;
      });
    }
  }

  Future<void> _shareRitual({
    required Ritual ritual,
    required RitualProgress? progress,
  }) async {
    if (_sharing) return;
    OverlayEntry? entry;
    try {
      setState(() {
        _sharing = true;
      });
      final overlay = Overlay.maybeOf(context, rootOverlay: true);
      if (overlay == null) {
        throw StateError("Overlay not available for ritual share");
      }
      await RitualShareCard.precacheAssets(context);
      final repaintKey = GlobalKey();
      entry = OverlayEntry(
        builder: (_) => Center(
          child: Material(
            type: MaterialType.transparency,
            child: IgnorePointer(
              child: Opacity(
                // Keep the share card invisible while still allowing it to paint.
                opacity: 0.01,
                child: RepaintBoundary(
                  key: repaintKey,
                  child: RitualShareCard(ritual: ritual, progress: progress),
                ),
              ),
            ),
          ),
        ),
      );
      overlay.insert(entry);
      final boundary = await _waitForBoundaryReady(repaintKey: repaintKey);
      if (!mounted) return;
      final double pixelRatio = (MediaQuery.devicePixelRatioOf(context) * 1.8)
          .clamp(2.4, 3.5);
      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final data = byteData?.buffer.asUint8List();
      if (data == null || data.isEmpty) {
        throw StateError("Unable to encode ritual share image");
      }
      final dir = await getTemporaryDirectory();
      final file = File(
        "${dir.path}/ritual_share_${ritual.id}_${DateTime.now().millisecondsSinceEpoch}.png",
      );
      await file.writeAsBytes(data, flush: true);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          sharePositionOrigin: shareButtonRect(context, _shareButtonKey),
        ),
      );
    } catch (e, s) {
      _logger.warning("Failed to share ritual", e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.ritualShareUnavailable)),
        );
      }
    } finally {
      entry?.remove();
      if (mounted) {
        setState(() {
          _sharing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RitualsState>(
      valueListenable: ritualsService.stateNotifier,
      builder: (context, state, _) {
        Ritual? ritual;
        for (final candidate in state.rituals) {
          if (candidate.id == widget.ritualId) {
            ritual = candidate;
            break;
          }
        }
        final currentRitual = ritual;
        if (currentRitual == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  context.l10n.ritualUntitled,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final progress = state.summary?.ritualProgress[currentRitual.id];
        final now = DateTime.now();
        final todayMidnight = DateTime(now.year, now.month, now.day);
        final lastStreakDay = _mostRecentStreakDay(
          ritual: currentRitual,
          progress: progress,
          todayMidnight: todayMidnight,
        );

        final colorScheme = getEnteColorScheme(context);
        final isDark = Theme.of(context).brightness == Brightness.dark;

        final actionBackground = isDark
            ? colorScheme.backgroundElevated2
            : const Color(0xFFF3F3F3);

        return Scaffold(
          appBar: AppBar(
            title: const SizedBox.shrink(),
            centerTitle: false,
            actions: [
              _TopActionButton(
                background: actionBackground,
                icon: HugeIcons.strokeRoundedCamera01,
                onPressed: () => openRitualCamera(context, currentRitual),
                tooltip: context.l10n.ritualOpenCameraTooltip,
              ),
              const SizedBox(width: 8),
              _TopActionButton(
                background: actionBackground,
                icon: HugeIcons.strokeRoundedShare08,
                buttonKey: _shareButtonKey,
                onPressed: _sharing
                    ? null
                    : () => _shareRitual(
                        ritual: currentRitual,
                        progress: progress,
                      ),
                tooltip: MaterialLocalizations.of(context).shareButtonLabel,
              ),
              const SizedBox(width: 8),
              _OverflowMenuButton(
                background: actionBackground,
                onEdit: () async {
                  await showRitualEditor(context, ritual: currentRitual);
                },
                onDelete: () async {
                  await _confirmAndDeleteRitual(currentRitual);
                },
              ),
              const SizedBox(width: 16),
            ],
          ),
          body: SafeArea(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
              children: [
                const SizedBox(height: 8),
                Center(
                  child: _StreakCircle(
                    streak: progress?.currentStreak ?? 0,
                    background: isDark
                        ? colorScheme.backgroundElevated2
                        : Theme.of(context).cardColor,
                  ),
                ),
                const SizedBox(height: 18),
                Center(child: _RitualHeader(ritual: currentRitual)),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _StreakStatCard(
                        label: "Longest this month",
                        streak: progress?.longestStreakThisMonth ?? 0,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _StreakStatCard(
                        label: "Longest overall",
                        streak: progress?.longestStreakOverall ?? 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _RecentDaysCard(ritual: currentRitual, progress: progress),
                const SizedBox(height: 18),
                _MonthOverviewCard(
                  ritual: currentRitual,
                  progress: progress,
                  visibleMonth: _visibleMonth,
                  lastStreakDay: lastStreakDay,
                  onPreviousMonth: _goToPreviousMonth,
                  onNextMonth: _goToNextMonth,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TopActionButton extends StatelessWidget {
  const _TopActionButton({
    required this.background,
    required this.icon,
    this.buttonKey,
    required this.onPressed,
    required this.tooltip,
  });

  final Color background;
  final List<List<dynamic>> icon;
  final Key? buttonKey;
  final VoidCallback? onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return IconButton(
      key: buttonKey,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.all(8),
        minimumSize: const Size(40, 40),
      ),
      icon: HugeIcon(icon: icon, size: 22, color: colorScheme.textBase),
      onPressed: onPressed,
    );
  }
}

enum _RitualOverflowAction { edit, delete }

class _OverflowMenuButton extends StatelessWidget {
  const _OverflowMenuButton({
    required this.background,
    required this.onEdit,
    required this.onDelete,
  });

  final Color background;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return PopupMenuButton<_RitualOverflowAction>(
      tooltip: MaterialLocalizations.of(context).showMenuTooltip,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      color: colorScheme.backgroundElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colorScheme.strokeFaint, width: 1),
      ),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _RitualOverflowAction.edit,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedPen01,
                color: colorScheme.textBase,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(context.l10n.edit),
            ],
          ),
        ),
        PopupMenuDivider(
          height: 0,
          thickness: 1,
          color: colorScheme.strokeFaint,
        ),
        PopupMenuItem(
          value: _RitualOverflowAction.delete,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              const HugeIcon(
                icon: HugeIcons.strokeRoundedDelete02,
                color: Colors.red,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                context.l10n.delete,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ),
        ),
      ],
      onSelected: (action) {
        switch (action) {
          case _RitualOverflowAction.edit:
            onEdit();
            break;
          case _RitualOverflowAction.delete:
            onDelete();
            break;
        }
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: HugeIcon(
            icon: HugeIcons.strokeRoundedMoreVertical,
            size: 22,
            color: colorScheme.textBase,
          ),
        ),
      ),
    );
  }
}

class _StreakCircle extends StatelessWidget {
  const _StreakCircle({required this.streak, required this.background});

  final int streak;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = streak.toString();

    const style = TextStyle(
      fontFamily: "Nunito",
      fontSize: 64,
      fontWeight: FontWeight.w900,
      letterSpacing: -1.6,
      height: 1,
    );
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textHeightBehavior: _tightTextHeightBehavior,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();

    const iconSize = 24.0;
    const lightningIconSize = iconSize * 1.25;
    Rect? rightMostDigitRect;
    for (var index = 0; index < text.length; index++) {
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: index, extentOffset: index + 1),
        boxHeightStyle: ui.BoxHeightStyle.tight,
        boxWidthStyle: ui.BoxWidthStyle.tight,
      );
      for (final box in boxes) {
        final rect = box.toRect();
        if (rightMostDigitRect == null ||
            rect.right > rightMostDigitRect.right) {
          rightMostDigitRect = rect;
        }
      }
    }
    final lastDigitRect = rightMostDigitRect ?? (Offset.zero & painter.size);
    final anchor = Offset(
      lastDigitRect.right - (painter.size.width / 2),
      lastDigitRect.bottom - (painter.size.height / 2),
    );
    final horizontalCenterShiftFactor = (0.25 - ((text.length - 1) * 0.065))
        .clamp(0.12, 0.25);
    final iconOffset = anchor.translate(
      iconSize * horizontalCenterShiftFactor,
      -(iconSize * 1.1),
    );

    final streakTextGradient = _linearGradientFromCssAngle(
      degrees: 178.24,
      colors: const [Color(0xFF545454), Color(0xFF000000)],
      stops: const [0.1192, 0.8251],
    );
    final streakLightningGradient = _linearGradientFromCssAngle(
      degrees: 189.82,
      colors: const [Color(0xFFFF9501), Color(0xFFFFD686)],
      stops: const [0.2622, 0.9524],
    );

    return Container(
      width: 132,
      height: 132,
      decoration: BoxDecoration(shape: BoxShape.circle, color: background),
      child: Center(
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            isDark
                ? Text(
                    text,
                    textHeightBehavior: _tightTextHeightBehavior,
                    style: style.copyWith(color: colorScheme.textBase),
                  )
                : _GradientText(
                    text,
                    gradient: streakTextGradient,
                    style: style,
                    textHeightBehavior: _tightTextHeightBehavior,
                  ),
            Transform.translate(
              offset: iconOffset,
              child: Transform.rotate(
                angle: 16 * math.pi / 180,
                child: isDark
                    ? const _LightningIcon(
                        size: lightningIconSize,
                        color: Color(0xFFFFB800),
                      )
                    : _LightningIcon(
                        size: lightningIconSize,
                        gradient: streakLightningGradient,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RitualHeader extends StatelessWidget {
  const _RitualHeader({required this.ritual});

  final Ritual ritual;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = ritual.title.isEmpty
        ? context.l10n.ritualUntitled
        : ritual.title;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: isDark
                ? colorScheme.backgroundElevated2
                : const Color(0xFFFAFAFA),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: RitualEmojiIcon(
                ritual.icon,
                style: textTheme.largeBold.copyWith(height: 1),
                textHeightBehavior: _tightTextHeightBehavior,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: textTheme.largeBold,
          textHeightBehavior: _tightTextHeightBehavior,
        ),
      ],
    );
  }
}

class _StreakStatCard extends StatelessWidget {
  const _StreakStatCard({required this.label, required this.streak});

  final String label;
  final int streak;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.backgroundElevated2
            : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.strokeFaint, width: 1),
      ),
      child: Column(
        children: [
          Text(label, style: textTheme.tinyMuted, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                streak.toString(),
                style: TextStyle(
                  fontFamily: "Nunito",
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.2,
                  height: 1,
                  color: colorScheme.textBase,
                ),
                textHeightBehavior: _tightTextHeightBehavior,
              ),
              const SizedBox(width: 6),
              const _LightningIcon(size: 16, color: Color(0xFFFFB800)),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentDaysCard extends StatelessWidget {
  const _RecentDaysCard({required this.ritual, required this.progress});

  final Ritual ritual;
  final RitualProgress? progress;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final preview = _ritualPreviewDays(
      ritual: ritual,
      progress: progress,
      todayMidnight: today,
      count: 4,
    );
    final days = preview.days;
    final showFuturePreview = preview.showFuturePreview;
    final completions = [
      for (final day in days) progress?.hasCompleted(day) ?? false,
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.backgroundElevated2
            : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.strokeFaint, width: 1),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 16.0;
          const slots = 5;
          final available = constraints.maxWidth - (spacing * (slots - 1));
          final tileWidth = available / slots;
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
                    ),
                  ),
                ),
              ],
              if (days.isNotEmpty) const SizedBox(width: spacing),
              Expanded(
                child: Align(
                  alignment: Alignment.center,
                  child: _AlbumChevronThumbnail(
                    width: tileWidth,
                    onTap: () => _openRitualAlbum(context, ritual),
                  ),
                ),
              ),
            ],
          );
        },
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
    final fadePhoto =
        completed && nextCompleted == false && !isYesterday && !isToday;
    final rotation = switch (index % 4) {
      0 => -0.05,
      1 => 0.10,
      2 => -0.08,
      _ => 0.08,
    };

    final variant = completed
        ? RitualDayThumbnailVariant.photo
        : (isToday
              ? RitualDayThumbnailVariant.camera
              : (showFuturePreview && day.isAfter(today)
                    ? RitualDayThumbnailVariant.future
                    : RitualDayThumbnailVariant.empty));

    final thumbnail = RitualDayThumbnail(
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
    final photoFile = file;
    if (variant != RitualDayThumbnailVariant.photo || photoFile == null) {
      return thumbnail;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () =>
            _openRitualAlbumAndFile(context, ritual: ritual, file: photoFile),
        borderRadius: BorderRadius.circular(12),
        child: thumbnail,
      ),
    );
  }
}

class _AlbumChevronThumbnail extends StatelessWidget {
  const _AlbumChevronThumbnail({required this.width, required this.onTap});

  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileHeight = width * (72 / 48);
    const labelHeight = 28.0;
    return SizedBox(
      width: width,
      height: tileHeight + 8 + labelHeight,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: isDark ? colorScheme.backgroundElevated : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark
                      ? colorScheme.strokeFaint
                      : Colors.black.withValues(alpha: 0.06),
                ),
              ),
              child: Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.textBase,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthOverviewCard extends StatelessWidget {
  const _MonthOverviewCard({
    required this.ritual,
    required this.progress,
    required this.visibleMonth,
    required this.lastStreakDay,
    required this.onPreviousMonth,
    required this.onNextMonth,
  });

  final Ritual ritual;
  final RitualProgress? progress;
  final DateTime visibleMonth;
  final DateTime? lastStreakDay;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final todayMidnight = DateTime(now.year, now.month, now.day);

    final canGoNext = visibleMonth.isBefore(currentMonth);
    final monthLabel = DateFormat.yMMM(
      Localizations.localeOf(context).toString(),
    ).format(visibleMonth);

    final weekdayLabels = _mondayFirstNarrowWeekdays(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.backgroundElevated2
            : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colorScheme.strokeFaint, width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  monthLabel,
                  style: textTheme.bodyBold.copyWith(
                    color: isDark
                        ? colorScheme.textBase
                        : const Color(0xFF454545),
                  ),
                  textHeightBehavior: _tightTextHeightBehavior,
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? colorScheme.backgroundElevated
                      : const Color(0xFFF3F3F3),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colorScheme.strokeFaint, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MonthChevronButton(
                      icon: Icons.chevron_left_rounded,
                      onTap: onPreviousMonth,
                      enabled: true,
                    ),
                    _MonthChevronButton(
                      icon: Icons.chevron_right_rounded,
                      onTap: onNextMonth,
                      enabled: canGoNext,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              for (final label in weekdayLabels)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: textTheme.miniMuted,
                      textHeightBehavior: _tightTextHeightBehavior,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _MonthGrid(
            ritual: ritual,
            progress: progress,
            visibleMonth: visibleMonth,
            todayMidnight: todayMidnight,
            lastStreakDay: lastStreakDay,
          ),
        ],
      ),
    );
  }
}

class _MonthChevronButton extends StatelessWidget {
  const _MonthChevronButton({
    required this.icon,
    required this.onTap,
    required this.enabled,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Material(
        color: isDark ? colorScheme.backgroundElevated2 : Colors.white,
        shape: CircleBorder(
          side: BorderSide(
            color: isDark
                ? colorScheme.strokeFaint
                : Colors.black.withValues(alpha: 0.06),
            width: 1,
          ),
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 28,
            height: 28,
            child: Icon(
              icon,
              size: 20,
              color: enabled ? colorScheme.textBase : colorScheme.textFaint,
            ),
          ),
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.ritual,
    required this.progress,
    required this.visibleMonth,
    required this.todayMidnight,
    required this.lastStreakDay,
  });

  final Ritual ritual;
  final RitualProgress? progress;
  final DateTime visibleMonth;
  final DateTime todayMidnight;
  final DateTime? lastStreakDay;

  static const _cellSize = 34.0;
  static const _cellSpacingX = 10.0;
  static const _cellSpacingY = 14.0;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);

    final firstDay = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final daysInMonth = DateTime(
      visibleMonth.year,
      visibleMonth.month + 1,
      0,
    ).day;
    final leadingEmpty = (firstDay.weekday + 6) % 7; // Monday-first
    final totalDaysCells = leadingEmpty + daysInMonth;
    final trailingEmpty = (7 - (totalDaysCells % 7)) % 7;
    final totalCells = totalDaysCells + trailingEmpty;

    final lastStreakKey = lastStreakDay == null
        ? null
        : DateTime(
            lastStreakDay!.year,
            lastStreakDay!.month,
            lastStreakDay!.day,
          ).millisecondsSinceEpoch;
    final todayKey = todayMidnight.millisecondsSinceEpoch;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: _cellSpacingY,
        crossAxisSpacing: _cellSpacingX,
        childAspectRatio: 1,
      ),
      itemCount: totalCells,
      itemBuilder: (context, index) {
        if (index < leadingEmpty || index >= leadingEmpty + daysInMonth) {
          return const SizedBox.shrink();
        }
        final dayNumber = index - leadingEmpty + 1;
        final day = DateTime(visibleMonth.year, visibleMonth.month, dayNumber);
        final dayKey = DateTime(
          day.year,
          day.month,
          day.day,
        ).millisecondsSinceEpoch;
        final enabled = _isEnabledDay(ritual, day);
        final completed = progress?.completedDayKeys.contains(dayKey) ?? false;
        final isToday = dayKey == todayKey;
        final isFuture = day.isAfter(todayMidnight);
        final isLastStreakDay =
            lastStreakKey != null && dayKey == lastStreakKey;

        if (!enabled) {
          return const _CrossedOutDay(size: _cellSize);
        }

        if (completed && isToday) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Center(
            child: _CompletedDayPill(
              background: isDark
                  ? colorScheme.backgroundElevated
                  : Colors.white,
              iconColor: const Color(0xFFFFB800),
            ),
          );
        }

        if (isLastStreakDay) {
          return const Center(
            child: _LightningIcon(size: 18, color: Color(0xFFFFB800)),
          );
        }

        if (completed) {
          return const Center(
            child: _CompletedDayPill(
              background: Color(0xFF1DB954),
              iconColor: Colors.white,
            ),
          );
        }

        return Center(
          child: Text(
            dayNumber.toString(),
            style: (isFuture ? textTheme.smallFaint : textTheme.small).copyWith(
              height: 1,
              color: isFuture ? colorScheme.textFaint : colorScheme.textMuted,
            ),
            textHeightBehavior: _tightTextHeightBehavior,
          ),
        );
      },
    );
  }
}

class _CompletedDayPill extends StatelessWidget {
  const _CompletedDayPill({required this.background, required this.iconColor});

  final Color background;
  final Color iconColor;

  static const _radius = BorderRadius.all(Radius.circular(10));

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _MonthGrid._cellSize,
      height: _MonthGrid._cellSize,
      decoration: BoxDecoration(color: background, borderRadius: _radius),
      child: Center(child: _LightningIcon(size: 16, color: iconColor)),
    );
  }
}

class _CrossedOutDay extends StatelessWidget {
  const _CrossedOutDay({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? colorScheme.backgroundElevated
        : const Color(0xFFF3F3F3);
    final stroke = isDark
        ? colorScheme.backgroundElevated2
        : Colors.black.withValues(alpha: 0.08);
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: ColoredBox(
            color: background,
            child: CustomPaint(
              painter: _CrossHatchPainter(
                color: stroke,
                strokeWidth: 1,
                gap: 5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CrossHatchPainter extends CustomPainter {
  const _CrossHatchPainter({
    required this.color,
    required this.strokeWidth,
    required this.gap,
  });

  final Color color;
  final double strokeWidth;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final diagonal = size.height;
    for (
      double startX = -diagonal;
      startX < size.width + diagonal;
      startX += gap
    ) {
      canvas.drawLine(
        Offset(startX, 0),
        Offset(startX + diagonal, diagonal),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CrossHatchPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.gap != gap;
  }
}

class _LightningIcon extends StatelessWidget {
  const _LightningIcon({required this.size, this.color, this.gradient})
    : assert(color != null || gradient != null);

  final double size;
  final Color? color;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      EnteIcons.lightningFilled,
      size: size,
      color: gradient == null ? color : Colors.white,
    );
    if (gradient == null) return icon;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => gradient!.createShader(bounds),
      child: icon,
    );
  }
}

Future<void> _openRitualAlbum(BuildContext context, Ritual ritual) async {
  final albumId = ritual.albumId;
  if (albumId == null || albumId <= 0) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.ritualAlbumMissing)));
    return;
  }
  final collection = CollectionsService.instance.getCollectionByID(albumId);
  if (collection == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.ritualAlbumMissing)));
    return;
  }
  final thumbnail = await CollectionsService.instance.getCover(collection);
  if (!context.mounted) return;
  await routeToPage(
    context,
    CollectionPage(
      CollectionWithThumbnail(collection, thumbnail),
      hasVerifiedLock: collection.isHidden(),
    ),
  );
}

Future<void> _openRitualAlbumAndFile(
  BuildContext context, {
  required Ritual ritual,
  required EnteFile file,
}) async {
  final albumId = ritual.albumId;
  if (albumId == null || albumId <= 0) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.ritualAlbumMissing)));
    return;
  }
  final collection = CollectionsService.instance.getCollectionByID(albumId);
  if (collection == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.ritualAlbumMissing)));
    return;
  }

  final thumbnail = await CollectionsService.instance.getCover(collection);
  if (!context.mounted) return;
  routeToPage(
    context,
    CollectionPage(
      CollectionWithThumbnail(collection, thumbnail),
      hasVerifiedLock: collection.isHidden(),
    ),
  ).ignore();

  final files = await FilesDB.instance.getAllFilesCollection(collection.id);
  final asc = collection.pubMagicMetadata.asc ?? false;
  files.sort((a, b) {
    final creationCompare = (a.creationTime ?? 0).compareTo(
      b.creationTime ?? 0,
    );
    if (creationCompare != 0) {
      return asc ? creationCompare : -creationCompare;
    }
    final modificationCompare = (a.modificationTime ?? 0).compareTo(
      b.modificationTime ?? 0,
    );
    return asc ? modificationCompare : -modificationCompare;
  });
  final selectedIndex = files.indexOf(file);
  if (selectedIndex < 0) return;

  if (!context.mounted) return;
  routeToPage(
    context,
    DetailPage(
      DetailPageConfiguration(files, selectedIndex, "ritual_${ritual.id}"),
    ),
    forceCustomPageRoute: true,
  ).ignore();
}

class _GradientText extends StatelessWidget {
  const _GradientText(
    this.text, {
    required this.gradient,
    required this.style,
    this.textHeightBehavior,
  });

  final String text;
  final Gradient gradient;
  final TextStyle style;
  final TextHeightBehavior? textHeightBehavior;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => gradient.createShader(bounds),
      child: Text(
        text,
        style: style.copyWith(color: Colors.white),
        textHeightBehavior: textHeightBehavior,
      ),
    );
  }
}

LinearGradient _linearGradientFromCssAngle({
  required double degrees,
  required List<Color> colors,
  List<double>? stops,
}) {
  final radians = degrees * math.pi / 180;
  final dx = math.sin(radians);
  final dy = -math.cos(radians);
  return LinearGradient(
    begin: Alignment(-dx, -dy),
    end: Alignment(dx, dy),
    colors: colors,
    stops: stops,
  );
}

DateTime? _mostRecentStreakDay({
  required Ritual ritual,
  required RitualProgress? progress,
  required DateTime todayMidnight,
}) {
  if (progress == null || progress.currentStreak <= 0) return null;
  final daysOfWeek = ritual.daysOfWeek;
  if (daysOfWeek.length != 7) return null;

  for (int offset = 0; offset < 366; offset++) {
    final day = todayMidnight.subtract(Duration(days: offset));
    final weekdayIndex = day.weekday % 7; // Sunday-first
    if (!_isScheduledDay(daysOfWeek, weekdayIndex)) continue;
    return progress.hasCompleted(day) ? day : null;
  }
  return null;
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

bool _isEnabledDay(Ritual ritual, DateTime day) {
  final daysOfWeek = ritual.daysOfWeek;
  if (daysOfWeek.length != 7) return true;
  if (!_hasAnyEnabledRitualDays(daysOfWeek)) return true;
  final weekdayIndex = day.weekday % 7; // Sunday-first
  return daysOfWeek[weekdayIndex];
}

List<String> _mondayFirstNarrowWeekdays(BuildContext context) {
  final labels = MaterialLocalizations.of(context).narrowWeekdays;
  if (labels.length != 7) {
    return const ["M", "T", "W", "T", "F", "S", "S"];
  }
  return [...labels.sublist(1), labels.first];
}

const _tightTextHeightBehavior = TextHeightBehavior(
  applyHeightToFirstAscent: false,
  applyHeightToLastDescent: false,
);

Future<RenderRepaintBoundary> _waitForBoundaryReady({
  required GlobalKey repaintKey,
}) async {
  const int maxAttempts = 8;
  const Duration attemptDelay = Duration(milliseconds: 40);

  for (int attempt = 0; attempt < maxAttempts; attempt++) {
    final boundary =
        repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    bool needsPaint = false;
    assert(() {
      needsPaint = boundary?.debugNeedsPaint ?? false;
      return true;
    }());
    if (boundary == null) {
      // no-op; wait and try again.
    } else if (boundary.size.isEmpty) {
      // no-op; wait and try again.
    } else if (needsPaint) {
      // no-op; wait and try again.
    } else {
      return boundary;
    }
    await WidgetsBinding.instance.endOfFrame;
    await Future.delayed(attemptDelay);
  }

  final boundary =
      repaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) {
    throw StateError("Render boundary unavailable for ritual share");
  }
  if (boundary.size.isEmpty) {
    throw StateError("Render boundary has zero size for ritual share");
  }
  bool needsPaint = false;
  assert(() {
    needsPaint = boundary.debugNeedsPaint;
    return true;
  }());
  if (needsPaint) {
    throw StateError("Render boundary not ready to paint for ritual share");
  }
  return boundary;
}
