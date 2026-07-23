import "dart:async";
import "dart:math" as math;

import "package:ente_components/theme/text_styles.dart";
import "package:ente_icons/ente_icons.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/rituals/ritual_models.dart";
import "package:photos/service_locator.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/rituals/all_rituals_screen.dart";
import "package:photos/ui/rituals/ritual_camera_page.dart";
import "package:photos/ui/rituals/ritual_editor_dialog.dart";
import "package:photos/ui/rituals/ritual_emoji_icon.dart";
import "package:photos/ui/rituals/ritual_page.dart";
import "package:photos/ui/rituals/ritual_privacy.dart";
import "package:photos/ui/rituals/start_new_ritual_card.dart";
import "package:photos/ui/viewer/search_tab/search_tab_horizontal_scroll.dart";

class RitualsBanner extends StatelessWidget {
  const RitualsBanner({super.key, required this.resultLimit});

  static const _cardRadius = 25.0;
  static const _minCardHeight = 94.0;
  static const _cardWidth = 167.5;

  final int resultLimit;

  @override
  Widget build(BuildContext context) {
    if (!flagService.ritualsFlag) {
      return const SizedBox.shrink();
    }
    return ValueListenableBuilder<RitualsState>(
      valueListenable: ritualsService.stateNotifier,
      builder: (context, state, _) {
        final rituals = state.rituals;
        final summary = state.summary;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: searchTabSectionHorizontalPadding,
              ),
              child: _RitualsHeader(
                showChevron: rituals.isNotEmpty,
                onTap: rituals.isNotEmpty
                    ? () => routeToPage(context, const AllRitualsScreen())
                    : null,
              ),
            ),
            const SizedBox(height: 4),
            if (rituals.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: searchTabSectionHorizontalPadding,
                ),
                child: StartNewRitualCard(
                  variant: StartNewRitualCardVariant.wide,
                  onTap: () async {
                    await _openNewRitualFromSearchTab(context);
                  },
                ),
              )
            else
              Builder(
                builder: (context) {
                  final cardHeight = _cardHeightFor(context);
                  final visibleRituals = rituals
                      .take(resultLimit)
                      .toList(growable: false);
                  return SearchTabHorizontalScrollView(
                    height: cardHeight,
                    child: Row(
                      children: [
                        for (final (index, item) in _buildRowItems(
                          context,
                          visibleRituals,
                          summary,
                          cardHeight,
                        ).indexed) ...[
                          if (index != 0) const SizedBox(width: 10),
                          item,
                        ],
                      ],
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  void _openNewRitualFlow(BuildContext context) {
    routeToPage(context, const AllRitualsScreen());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!context.mounted) return;
      await showRitualEditor(context, ritual: null);
    });
  }

  Future<void> _openNewRitualFromSearchTab(BuildContext context) async {
    final existingRitualIds = ritualsService.stateNotifier.value.rituals
        .map((ritual) => ritual.id)
        .toSet();
    await showRitualEditor(context, ritual: null);
    if (!context.mounted) return;

    Ritual? createdRitual;
    for (final ritual in ritualsService.stateNotifier.value.rituals) {
      if (!existingRitualIds.contains(ritual.id)) {
        createdRitual = ritual;
        break;
      }
    }
    if (createdRitual == null) return;
    final canOpen = await requestHiddenRitualAccess(context, createdRitual);
    if (!context.mounted || !canOpen) return;
    unawaited(routeToPage(context, RitualPage(ritualId: createdRitual.id)));
  }

  List<Widget> _buildRowItems(
    BuildContext context,
    List<Ritual> rituals,
    RitualsSummary? summary,
    double cardHeight,
  ) {
    return [
      for (final ritual in rituals)
        _RitualSummaryCard(
          ritual: ritual,
          progress: summary?.ritualProgress[ritual.id],
          height: cardHeight,
        ),
      if (rituals.isNotEmpty)
        StartNewRitualCard(
          variant: StartNewRitualCardVariant.compact,
          onTap: () => _openNewRitualFlow(context),
          compactHeight: cardHeight,
        ),
    ];
  }

  static double _cardHeightFor(BuildContext context) {
    return math.max(
      _summaryCardHeightFor(context),
      StartNewRitualCard.compactHeightFor(context),
    );
  }

  static double _summaryCardHeightFor(BuildContext context) {
    const verticalPadding = 32.0;
    const rowGap = 4.0;
    final titleRowHeight = math.max(
      28.0,
      _singleLineTextHeight(context, _ritualSummaryTitleStyle(Colors.black)),
    );
    final actionRowHeight = math.max(
      28.0,
      _singleLineTextHeight(context, _streakTextStyle),
    );
    return math.max(
      _minCardHeight,
      verticalPadding + titleRowHeight + rowGap + actionRowHeight,
    );
  }
}

class _RitualsHeader extends StatelessWidget {
  const _RitualsHeader({required this.showChevron, required this.onTap});

  final bool showChevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 38,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              context.l10n.ritualsTitle,
              style: TextStyles.display3.copyWith(color: colorScheme.textBase),
            ),
            if (showChevron)
              Container(
                color: Colors.transparent,
                width: 38,
                height: 38,
                child: Icon(
                  Icons.chevron_right_outlined,
                  color: colorScheme.blurStrokePressed,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RitualSummaryCard extends StatelessWidget {
  const _RitualSummaryCard({
    required this.ritual,
    required this.progress,
    required this.height,
  });

  final Ritual ritual;
  final RitualProgress? progress;
  final double height;

  static const _cardRadius = RitualsBanner._cardRadius;
  static const _cardWidth = RitualsBanner._cardWidth;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final streak = progress?.currentStreak ?? 0;

    return SizedBox(
      width: _cardWidth,
      height: height,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(_cardRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(_cardRadius),
          onTap: () async {
            final canOpen = await requestHiddenRitualAccess(context, ritual);
            if (!context.mounted || !canOpen) return;
            unawaited(routeToPage(context, RitualPage(ritualId: ritual.id)));
          },
          child: Container(
            decoration: BoxDecoration(
              color: colorScheme.fill,
              borderRadius: BorderRadius.circular(_cardRadius),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _RitualIcon(ritual: ritual),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        ritual.title.isEmpty
                            ? context.l10n.ritualUntitled
                            : ritual.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _ritualSummaryTitleStyle(colorScheme.textBase),
                        textHeightBehavior: _tightTextHeightBehavior,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _StreakIndicator(streak: streak),
                    const Spacer(),
                    _RitualCameraButton(
                      onTap: () => openRitualCamera(context, ritual),
                      tooltip: context.l10n.ritualOpenCameraTooltip,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RitualIcon extends StatelessWidget {
  const _RitualIcon({required this.ritual});

  final Ritual ritual;

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    return SizedBox(
      width: 28,
      height: 28,
      child: Center(
        child: RitualEmojiIcon(
          ritual.icon,
          style: textTheme.body.copyWith(fontSize: 18, height: 1),
          textHeightBehavior: _tightTextHeightBehavior,
        ),
      ),
    );
  }
}

class _StreakIndicator extends StatelessWidget {
  const _StreakIndicator({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _StreakNumber(streak: streak),
        const SizedBox(width: 4),
        const _LightningIcon(),
      ],
    );
  }
}

class _StreakNumber extends StatelessWidget {
  const _StreakNumber({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final text = streak.toString();

    return Text(
      text,
      style: _streakTextStyle.copyWith(color: colorScheme.textBase),
      textHeightBehavior: _tightTextHeightBehavior,
    );
  }
}

const _streakTextStyle = TextStyle(
  fontFamily: TextStyles.outfitFontFamily,
  package: TextStyles.fontPackage,
  fontSize: 24,
  fontWeight: FontWeight.w900,
  letterSpacing: -0.96,
  height: 1,
);

class _LightningIcon extends StatelessWidget {
  const _LightningIcon();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 17,
      child: Center(
        child: Icon(
          EnteIcons.lightningFilled,
          size: 17,
          color: Color(0xFFFFBC03),
        ),
      ),
    );
  }
}

class _RitualCameraButton extends StatelessWidget {
  const _RitualCameraButton({required this.onTap, required this.tooltip});

  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final borderRadius = BorderRadius.circular(12);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Center(
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedCamera01,
                size: 18,
                color: colorScheme.textBase,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _tightTextHeightBehavior = TextHeightBehavior(
  applyHeightToFirstAscent: false,
  applyHeightToLastDescent: false,
);

TextStyle _ritualSummaryTitleStyle(Color color) {
  return TextStyles.bodyBold.copyWith(color: color);
}

double _singleLineTextHeight(BuildContext context, TextStyle style) {
  final textPainter = TextPainter(
    text: TextSpan(text: "Ag", style: style),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    textHeightBehavior: _tightTextHeightBehavior,
  )..layout();
  return textPainter.height;
}
