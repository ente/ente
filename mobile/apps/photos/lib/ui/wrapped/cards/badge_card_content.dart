part of 'package:photos/ui/wrapped/wrapped_viewer_page.dart';

Widget? buildBadgeCardContent(
  WrappedCard card,
  EnteColorScheme colorScheme,
  EnteTextTheme textTheme,
) {
  if (card.type != WrappedCardType.badge) {
    return null;
  }
  return _BadgeCardContent(
    card: card,
    colorScheme: colorScheme,
    textTheme: textTheme,
  );
}

class _BadgeCardContent extends StatelessWidget {
  const _BadgeCardContent({
    required this.card,
    required this.colorScheme,
    required this.textTheme,
  });

  final WrappedCard card;
  final EnteColorScheme colorScheme;
  final EnteTextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final _BadgeVisuals visuals = _badgeVisualsFor(card);
    final _WrappedViewerPageState? viewerState = context
        .findAncestorStateOfType<_WrappedViewerPageState>();
    final bool hideSharePill = viewerState?.hideBadgeSharePill ?? false;

    final _BadgeLayoutConstants layout = _BadgeLayoutConstants(
      textTheme: textTheme,
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final _BadgeLayoutMetrics metrics = _BadgeLayoutMetrics.fromConstraints(
          constraints,
        );
        final TextStyle titleStyle = layout.titleStyle(metrics.scale);
        final TextStyle subtitleStyle = layout.subtitleStyle(metrics.scale);
        final TextStyle shareStyle = layout.shareLabelStyle(metrics.scale);

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: metrics.cardWidth,
            height: metrics.cardHeight,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(metrics.outerRadius),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Positioned.fill(child: ColoredBox(color: Colors.white)),
                  Positioned(
                    left: metrics.panelLeft,
                    top: metrics.panelTop,
                    width: metrics.panelWidth,
                    height: metrics.panelHeight,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(metrics.panelRadius),
                      child: Stack(
                        clipBehavior: Clip.hardEdge,
                        children: [
                          const Positioned.fill(
                            child: ColoredBox(color: _kBadgeBaseGreen),
                          ),
                          Positioned(
                            left: metrics.panelRaysLeft,
                            top: metrics.panelRaysTop,
                            width: metrics.panelRaysWidth,
                            height: metrics.panelRaysHeight,
                            child: IgnorePointer(
                              child: Opacity(
                                opacity: 0.82,
                                child: Image.asset(
                                  _BadgeVisualAssets.rays,
                                  fit: BoxFit.fill,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: metrics.panelCloudLeft,
                            right: metrics.panelCloudRight,
                            bottom: metrics.panelCloudBottom,
                            height: metrics.panelCloudHeight,
                            child: IgnorePointer(
                              child: Image.asset(
                                _BadgeVisualAssets.cloud,
                                fit: BoxFit.cover,
                                color: _kBadgeCloudTint,
                                colorBlendMode: BlendMode.srcATop,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: metrics.duckLeft,
                    top: metrics.duckTop,
                    width: metrics.duckWidth,
                    height: metrics.duckHeight,
                    child: Image.asset(
                      visuals.illustrationAsset,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  Positioned(
                    left: metrics.titleLeft,
                    top: metrics.titleTop,
                    width: metrics.textWidth,
                    child: Text(
                      card.title,
                      style: titleStyle,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (card.subtitle != null && card.subtitle!.isNotEmpty)
                    Positioned(
                      left: metrics.titleLeft,
                      top: metrics.subtitleTop,
                      width: metrics.textWidth,
                      child: Text(
                        card.subtitle!,
                        style: subtitleStyle,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  Positioned(
                    left: metrics.logoLeft,
                    top: metrics.logoTop,
                    width: metrics.logoBoundingSize,
                    height: metrics.logoBoundingSize,
                    child: Center(
                      child: SizedBox.square(
                        dimension: metrics.logoSize,
                        child: const _BadgeBrandLogo(),
                      ),
                    ),
                  ),
                  Positioned(
                    left: metrics.shareLeft,
                    top: metrics.shareTop,
                    width: metrics.shareWidth,
                    height: metrics.shareHeight,
                    child: IgnorePointer(
                      ignoring: hideSharePill,
                      child: Opacity(
                        opacity: hideSharePill ? 0.0 : 1.0,
                        child: _BadgeSharePill(
                          labelStyle: shareStyle,
                          onTap: viewerState == null
                              ? null
                              : () => unawaited(viewerState.shareCurrentCard()),
                          shareButtonKey: null,
                          size: Size(metrics.shareWidth, metrics.shareHeight),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BadgeVisuals {
  const _BadgeVisuals({required this.illustrationAsset});

  final String illustrationAsset;
}

class _BadgeVisualAssets {
  static const String cloud = "assets/rewind_badges/cloud-effect.png";
  static const String rays = "assets/rewind_badges/rays.png";
  static const String logo = "assets/launcher_icon/icon-foreground.png";
  static const String peoplePerson = "assets/rewind_badges/people_person.png";
  static const String consistencyChamp =
      "assets/rewind_badges/consistency_champ.png";
  static const String globetrotter = "assets/rewind_badges/globetrotter.png";
  static const String minimalist =
      "assets/rewind_badges/minimalist_shooter.png";
  static const String portraitPro = "assets/rewind_badges/portrait_pro.png";
}

const double _kBadgeDesignWidth = 349.0;
const double _kBadgeDesignHeight = 581.0;
const double _kDesignPanelLeft = 10.0;
const double _kDesignPanelTop = 147.0;
const double _kDesignPanelWidth = 329.0;
const double _kDesignPanelHeight = 424.0;
const double _kDesignPanelRadius = 27.0;
// The rays asset has a large transparent top margin. Offset it far enough so
// the visible portion hugs the panel's top edge, and extend the height so the
// lower edge stays aligned with the duck illustration.
const double _kDesignRaysTopOffset = -108.0;
const double _kDesignRaysHeight = 248.0;
const double _kDesignRaysLeftInset = -18.0;
const double _kDesignRaysRightInset = -18.0;
const double _kDesignCloudInset = 0.0;
const double _kDesignCloudHeight = 100.0;
const double _kDesignCloudBottom = -6.0;
const double _kDesignDuckTop = 106.0;
const double _kDesignDuckWidth = 280.0;
const double _kDesignDuckHeight = 202.0;
const double _kDesignTitleLeft = _kDesignPanelLeft;
const double _kDesignTitleTop = 342.0;
const double _kDesignSubtitleTop = 388.0;
const double _kDesignShareWidth = 122.27;
const double _kDesignShareHeight = 56.93;
const double _kDesignLogoSize = 64.0;
const double _kDesignLogoBoundingSize = 76.0;
const double _kDesignTextWidth = _kDesignPanelWidth;
const double _kDesignPanelContentPadding = 3.0;
const double _kDesignShareShadowBlur = 6.0;
const double _kDesignShareShadowOffsetY = 3.0;
const double _kDesignLogoOffsetLeft = 21.0;
const double _kDesignLogoOffsetBottom = 20.0;
const double _kDesignLogoPaddingAdjust = 3.0;

class _BadgeLayoutConstants {
  const _BadgeLayoutConstants({required this.textTheme});

  final EnteTextTheme textTheme;

  TextStyle titleStyle(double scale) {
    return textTheme.h2Bold.copyWith(
      color: Colors.white,
      fontSize: textTheme.h2Bold.fontSize != null
          ? textTheme.h2Bold.fontSize! * scale
          : 48.0 * scale,
      height: 1.1,
    );
  }

  TextStyle subtitleStyle(double scale) {
    final double fontSize = 18.0 * scale;
    return textTheme.bodyMuted.copyWith(
      color: Colors.white,
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.9 * scale,
      height: 1.25,
    );
  }

  TextStyle shareLabelStyle(double scale) {
    final double fontSize = 24.0 * scale;
    return textTheme.h3Bold.copyWith(
      color: _kBadgeBaseGreen,
      fontSize: fontSize,
      letterSpacing: -1.1 * scale,
      height: 1.1,
    );
  }
}

class _BadgeLayoutMetrics {
  const _BadgeLayoutMetrics._({
    required this.scale,
    required this.cardWidth,
    required this.cardHeight,
    required this.outerRadius,
    required this.panelLeft,
    required this.panelTop,
    required this.panelWidth,
    required this.panelHeight,
    required this.panelRadius,
    required this.panelRaysLeft,
    required this.panelRaysTop,
    required this.panelRaysWidth,
    required this.panelRaysHeight,
    required this.panelCloudLeft,
    required this.panelCloudRight,
    required this.panelCloudBottom,
    required this.panelCloudHeight,
    required this.duckLeft,
    required this.duckTop,
    required this.duckWidth,
    required this.duckHeight,
    required this.titleLeft,
    required this.titleTop,
    required this.subtitleTop,
    required this.textWidth,
    required this.shareLeft,
    required this.shareTop,
    required this.shareWidth,
    required this.shareHeight,
    required this.logoLeft,
    required this.logoTop,
    required this.logoSize,
    required this.logoBoundingSize,
  });

  final double scale;
  final double cardWidth;
  final double cardHeight;
  final double outerRadius;

  final double panelLeft;
  final double panelTop;
  final double panelWidth;
  final double panelHeight;
  final double panelRadius;

  final double panelRaysLeft;
  final double panelRaysTop;
  final double panelRaysWidth;
  final double panelRaysHeight;

  final double panelCloudLeft;
  final double panelCloudRight;
  final double panelCloudBottom;
  final double panelCloudHeight;

  final double duckLeft;
  final double duckTop;
  final double duckWidth;
  final double duckHeight;

  final double titleLeft;
  final double titleTop;
  final double subtitleTop;
  final double textWidth;

  final double shareLeft;
  final double shareTop;
  final double shareWidth;
  final double shareHeight;

  final double logoLeft;
  final double logoTop;
  final double logoSize;
  final double logoBoundingSize;

  static _BadgeLayoutMetrics fromConstraints(BoxConstraints constraints) {
    final double availableWidth = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : double.infinity;
    final double availableHeight = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : double.infinity;
    double scale = 1.0;
    if (availableWidth.isFinite && availableHeight.isFinite) {
      scale = math.min(
        availableWidth / _kBadgeDesignWidth,
        availableHeight / _kBadgeDesignHeight,
      );
    } else if (availableWidth.isFinite) {
      scale = availableWidth / _kBadgeDesignWidth;
    } else if (availableHeight.isFinite) {
      scale = availableHeight / _kBadgeDesignHeight;
    }
    scale = math.max(0.7, math.min(scale, 1.6));

    final double cardWidth = _kBadgeDesignWidth * scale;
    final double cardHeight = _kBadgeDesignHeight * scale;
    final double outerRadius = 33.0 * scale;
    final double panelLeft = _kDesignPanelLeft * scale;
    final double panelTop = _kDesignPanelTop * scale;
    final double panelWidth = _kDesignPanelWidth * scale;
    final double panelHeight = _kDesignPanelHeight * scale;

    final double duckWidth = _kDesignDuckWidth * scale;
    final double duckHeight = _kDesignDuckHeight * scale;
    final double duckLeft = (cardWidth - duckWidth) / 2;
    final double duckTop = _kDesignDuckTop * scale;

    final double titleLeft = _kDesignTitleLeft * scale;
    final double textWidth = math.max(_kDesignTextWidth, 160.0) * scale;

    final double shareWidth = _kDesignShareWidth * scale;
    final double shareHeight = _kDesignShareHeight * scale;
    final double shareShadowBlur = _kDesignShareShadowBlur * scale;
    final double shareShadowOffsetY = _kDesignShareShadowOffsetY * scale;

    final double logoSize = _kDesignLogoSize * scale;
    final double logoBoundingSize = _kDesignLogoBoundingSize * scale;
    final double logoOffsetLeft = _kDesignLogoOffsetLeft * scale;
    final double logoOffsetBottom = _kDesignLogoOffsetBottom * scale;

    return _BadgeLayoutMetrics._(
      scale: scale,
      cardWidth: cardWidth,
      cardHeight: cardHeight,
      panelLeft: panelLeft,
      panelTop: panelTop,
      panelWidth: panelWidth,
      panelHeight: panelHeight,
      panelRadius: _kDesignPanelRadius * scale,
      panelRaysLeft: _kDesignRaysLeftInset * scale,
      panelRaysTop: _kDesignRaysTopOffset * scale,
      panelRaysWidth:
          (panelWidth -
          (_kDesignRaysLeftInset + _kDesignRaysRightInset) * scale),
      panelRaysHeight: _kDesignRaysHeight * scale,
      panelCloudLeft: _kDesignCloudInset * scale,
      panelCloudRight: _kDesignCloudInset * scale,
      panelCloudBottom: _kDesignCloudBottom * scale,
      panelCloudHeight: _kDesignCloudHeight * scale,
      duckLeft: duckLeft,
      duckTop: duckTop,
      duckWidth: duckWidth,
      duckHeight: duckHeight,
      titleLeft: titleLeft,
      titleTop: _kDesignTitleTop * scale,
      subtitleTop: _kDesignSubtitleTop * scale,
      textWidth: textWidth,
      shareLeft:
          panelLeft +
          panelWidth -
          shareWidth -
          _kDesignPanelContentPadding -
          shareShadowBlur,
      shareTop:
          panelTop +
          panelHeight -
          shareHeight -
          _kDesignPanelContentPadding -
          shareShadowOffsetY -
          shareShadowBlur,
      shareWidth: shareWidth,
      shareHeight: shareHeight,
      logoLeft:
          panelLeft +
          _kDesignPanelContentPadding +
          _kDesignLogoPaddingAdjust -
          logoOffsetLeft,
      logoTop:
          panelTop +
          panelHeight -
          (logoBoundingSize - logoOffsetBottom) -
          _kDesignPanelContentPadding -
          _kDesignLogoPaddingAdjust,
      logoSize: logoSize,
      logoBoundingSize: logoBoundingSize,
      outerRadius: outerRadius,
    );
  }
}

const Map<String, String> _kBadgeIllustrations = <String, String>{
  "people_person": _BadgeVisualAssets.peoplePerson,
  "consistency_champ": _BadgeVisualAssets.consistencyChamp,
  "globetrotter": _BadgeVisualAssets.globetrotter,
  "minimalist_shooter": _BadgeVisualAssets.minimalist,
  "portrait_pro": _BadgeVisualAssets.portraitPro,
};

_BadgeVisuals _badgeVisualsFor(WrappedCard card) {
  final String badgeKey =
      (card.meta["badgeKey"] as String?)?.toLowerCase() ?? "";
  final String asset =
      _kBadgeIllustrations[badgeKey] ?? _BadgeVisualAssets.peoplePerson;
  return _BadgeVisuals(illustrationAsset: asset);
}

class _BadgeBrandLogo extends StatelessWidget {
  const _BadgeBrandLogo();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: _kBadgeLogoRotationRadians,
      child: Image.asset(_BadgeVisualAssets.logo, fit: BoxFit.contain),
    );
  }
}

class _BadgeSharePill extends StatelessWidget {
  const _BadgeSharePill({
    required this.labelStyle,
    required this.size,
    this.onTap,
    this.shareButtonKey,
  });

  final TextStyle labelStyle;
  final VoidCallback? onTap;
  final GlobalKey? shareButtonKey;
  final Size size;

  @override
  Widget build(BuildContext context) {
    final double shadowScale = size.height / _kDesignShareHeight;
    return GestureDetector(
      onTap: onTap,
      child: RepaintBoundary(
        key: shareButtonKey,
        child: Container(
          width: size.width,
          height: size.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(size.height / 2),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 16 * shadowScale,
                offset: Offset(0, 8 * shadowScale),
              ),
            ],
          ),
          child: Text("Share", style: labelStyle),
        ),
      ),
    );
  }
}

const Color _kBadgeBaseGreen = Color(0xFF08C225);
const Color _kBadgeCloudTint = Color(0xFF0BCA29);
const double _kBadgeLogoRotationRadians = -9.91 * math.pi / 180;

Widget? buildBadgeDebugCardContent(
  WrappedCard card,
  EnteColorScheme colorScheme,
  EnteTextTheme textTheme,
) {
  if (card.type != WrappedCardType.badgeDebug) {
    return null;
  }
  return _BadgeDebugCardContent(
    card: card,
    colorScheme: colorScheme,
    textTheme: textTheme,
  );
}

class _BadgeDebugCardContent extends StatelessWidget {
  const _BadgeDebugCardContent({
    required this.card,
    required this.colorScheme,
    required this.textTheme,
  });

  final WrappedCard card;
  final EnteColorScheme colorScheme;
  final EnteTextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final List<Map<String, Object?>> candidates = _mapListFromMeta(
      card.meta,
      "candidates",
    );
    if (candidates.isEmpty) {
      return const SizedBox.shrink();
    }
    candidates.sort((Map<String, Object?> a, Map<String, Object?> b) {
      final bool eligibleA = a["eligible"] as bool? ?? false;
      final bool eligibleB = b["eligible"] as bool? ?? false;
      if (eligibleA != eligibleB) {
        return eligibleB ? 1 : -1;
      }
      final double scoreA =
          (a["score"] as num?)?.toDouble() ?? double.negativeInfinity;
      final double scoreB =
          (b["score"] as num?)?.toDouble() ?? double.negativeInfinity;
      final int scoreCompare = scoreB.compareTo(scoreA);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      final int tierA = a["tier"] as int? ?? 0;
      final int tierB = b["tier"] as int? ?? 0;
      final int tierCompare = tierA.compareTo(tierB);
      if (tierCompare != 0) {
        return tierCompare;
      }
      final String keyA = a["key"] as String? ?? "";
      final String keyB = b["key"] as String? ?? "";
      return keyA.compareTo(keyB);
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Badge candidates (debug)",
          style: textTheme.h2Bold.copyWith(color: colorScheme.fillStrong),
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 600),
          child: Scrollbar(
            thumbVisibility: true,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: candidates.length,
              itemBuilder: (BuildContext context, int index) {
                return _BadgeCandidateDebugRow(
                  index: index,
                  data: candidates[index],
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _BadgeCandidateDebugRow extends StatelessWidget {
  const _BadgeCandidateDebugRow({
    required this.index,
    required this.data,
    required this.colorScheme,
    required this.textTheme,
  });

  final int index;
  final Map<String, Object?> data;
  final EnteColorScheme colorScheme;
  final EnteTextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final String name = data["name"] as String? ?? data["key"] as String? ?? "";
    final double? score = (data["score"] as num?)?.toDouble();
    final bool eligible = data["eligible"] as bool? ?? false;
    final int tier = data["tier"] as int? ?? 1;
    final String debugWhy = data["debugWhy"] as String? ?? "";
    final String badgeKey = data["key"] as String? ?? "";

    final TextStyle titleStyle = textTheme.smallBold.copyWith(
      color: eligible ? colorScheme.fillStrong : colorScheme.fillMuted,
    );
    final TextStyle subtitleStyle = textTheme.smallMuted.copyWith(
      color: colorScheme.fillMuted,
    );
    final List<Color> gradientColors = _extractGradientColors(
      data,
      colorScheme,
    );
    final String? subtitle = data["subtitle"] as String?;
    final String? emoji = data["emoji"] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: gradientColors.length >= 2
              ? LinearGradient(
                  colors: gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: gradientColors.isEmpty ? colorScheme.backgroundElevated : null,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (emoji != null && emoji.isNotEmpty) ...[
                  Text(emoji, style: textTheme.h2Bold.copyWith(fontSize: 24)),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    "${index + 1}. $name",
                    style: titleStyle.copyWith(color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (score != null)
                  Text(
                    score.toStringAsFixed(2),
                    style: titleStyle.copyWith(
                      color: Colors.white,
                      fontFeatures: const <ui.FontFeature>[
                        ui.FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
              ],
            ),
            if (subtitle != null && subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: textTheme.smallMuted.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              "Tier $tier • ${eligible ? "eligible" : "ineligible"} • $badgeKey",
              style: subtitleStyle.copyWith(color: Colors.white70),
            ),
            if (debugWhy.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                debugWhy,
                style: subtitleStyle.copyWith(color: Colors.white70),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

List<Map<String, Object?>> _mapListFromMeta(
  Map<String, Object?> meta,
  String key,
) {
  final Object? value = meta[key];
  if (value is List) {
    return value
        .whereType<Map>()
        .map((Map raw) => raw.cast<String, Object?>())
        .toList(growable: false);
  }
  return const <Map<String, Object?>>[];
}

List<Color> _extractGradientColors(
  Map<String, Object?> data,
  EnteColorScheme scheme,
) {
  final Object? raw = data["gradient"];
  if (raw is! List) {
    return <Color>[];
  }
  final List<Color> colors = <Color>[];
  for (final Object? entry in raw) {
    if (entry is String) {
      colors.add(_colorFromHex(entry, scheme.primary500));
    }
  }
  return colors;
}
