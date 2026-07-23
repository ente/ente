part of 'package:photos/ui/wrapped/wrapped_viewer_page.dart';

Widget? buildPlacesCardContent(
  WrappedCard card,
  EnteColorScheme colorScheme,
  EnteTextTheme textTheme,
) {
  switch (card.type) {
    case WrappedCardType.topCities:
      return _TopCitiesCardContent(
        card: card,
        colorScheme: colorScheme,
        textTheme: textTheme,
      );
    case WrappedCardType.mostVisitedSpot:
      return _MostVisitedSpotCardContent(
        card: card,
        colorScheme: colorScheme,
        textTheme: textTheme,
      );
    default:
      return null;
  }
}

class _TopCitiesCardContent extends StatelessWidget {
  const _TopCitiesCardContent({
    required this.card,
    required this.colorScheme,
    required this.textTheme,
  });

  final WrappedCard card;
  final EnteColorScheme colorScheme;
  final EnteTextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final List<_CityShareStat> stats = _cityShareStatsFromMeta(card.meta);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroMediaCollage(media: card.media, colorScheme: colorScheme),
        const SizedBox(height: 24),
        buildWrappedCardTitle(card.title, textTheme.h2Bold),
        if (card.subtitle != null && card.subtitle!.isNotEmpty)
          buildWrappedCardSubtitle(
            card.subtitle!,
            textTheme.bodyMuted,
            padding: const EdgeInsets.only(top: 12),
          ),
        if (stats.isNotEmpty) ...[
          const SizedBox(height: 22),
          _CityShareList(
            stats: stats,
            colorScheme: colorScheme,
            textTheme: textTheme,
          ),
        ],
        const Spacer(),
      ],
    );
  }
}

class _CityShareList extends StatelessWidget {
  const _CityShareList({
    required this.stats,
    required this.colorScheme,
    required this.textTheme,
  });

  final List<_CityShareStat> stats;
  final EnteColorScheme colorScheme;
  final EnteTextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final (int index, _CityShareStat stat) in stats.indexed)
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 16),
            child: _CityShareRow(
              stat: stat,
              colorScheme: colorScheme,
              textTheme: textTheme,
            ),
          ),
      ],
    );
  }
}

class _CityShareRow extends StatelessWidget {
  const _CityShareRow({
    required this.stat,
    required this.colorScheme,
    required this.textTheme,
  });

  final _CityShareStat stat;
  final EnteColorScheme colorScheme;
  final EnteTextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final double progress = (stat.sharePercent.clamp(0, 100)) / 100.0;
    final String countLabel =
        "${stat.count} ${stat.count == 1 ? 'shot' : 'shots'}";
    final String detailsLabel = stat.distinctDays <= 1
        ? countLabel
        : "$countLabel · ${stat.distinctDays} days";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                stat.label,
                style: textTheme.bodyBold,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            Text("${stat.sharePercent}%", style: textTheme.smallMuted),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            children: [
              Container(height: 6, color: colorScheme.fillFaint),
              FractionallySizedBox(
                widthFactor: progress,
                child: Container(height: 6, color: colorScheme.primary500),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(detailsLabel, style: textTheme.smallMuted),
      ],
    );
  }
}

class _CityShareStat {
  _CityShareStat({
    required this.label,
    required this.count,
    required this.sharePercent,
    required this.distinctDays,
  });

  final String label;
  final int count;
  final int sharePercent;
  final int distinctDays;
}

List<_CityShareStat> _cityShareStatsFromMeta(Map<String, Object?> meta) {
  final Object? raw = meta["cities"];
  if (raw is! List) {
    return const <_CityShareStat>[];
  }

  final List<_CityShareStat> stats = <_CityShareStat>[];
  for (final Object? entry in raw) {
    if (entry is! Map) {
      continue;
    }
    final Map<String, Object?> map = entry.cast<String, Object?>();
    final String? displayLabel = (map["displayLabel"] as String?)?.trim();
    final String? name = (map["name"] as String?)?.trim();
    final String? country = (map["country"] as String?)?.trim();
    final String? label = displayLabel?.isNotEmpty == true
        ? displayLabel
        : (name?.isNotEmpty == true ? name : country);
    final int count = (map["count"] as num?)?.toInt() ?? 0;
    final int sharePercent = (map["sharePercent"] as num?)?.round() ?? 0;
    final int distinctDays = (map["distinctDays"] as num?)?.toInt() ?? 0;
    if (label == null || label.isEmpty || count <= 0) {
      continue;
    }
    stats.add(
      _CityShareStat(
        label: label,
        count: count,
        sharePercent: sharePercent.clamp(0, 100),
        distinctDays: distinctDays,
      ),
    );
  }
  return stats;
}

class _MostVisitedSpotCardContent extends StatelessWidget {
  const _MostVisitedSpotCardContent({
    required this.card,
    required this.colorScheme,
    required this.textTheme,
  });

  final WrappedCard card;
  final EnteColorScheme colorScheme;
  final EnteTextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final List<String> chips = _stringListFromMeta(card.meta, "detailChips");
    final List<MediaRef> extraMedia = card.media
        .skip(3)
        .toList(growable: false);
    final List<MediaRef> secondRowMedia = extraMedia
        .take(3)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroMediaCollage(media: card.media, colorScheme: colorScheme),
        if (secondRowMedia.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: List<Widget>.generate(2, (int index) {
                      final MediaRef? ref = index < secondRowMedia.length
                          ? secondRowMedia[index]
                          : null;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: index == 0 ? 12 : 0),
                          child: ref != null
                              ? _MediaTile(mediaRef: ref, borderRadius: 20)
                              : _MediaPlaceholder(
                                  colorScheme: colorScheme,
                                  borderRadius: 20,
                                ),
                        ),
                      );
                    }),
                  ),
                ),
                if (secondRowMedia.length == 3) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _MediaTile(
                      mediaRef: secondRowMedia[2],
                      borderRadius: 24,
                      aspectRatio: 3 / 4,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),
        buildWrappedCardTitle(card.title, textTheme.h2Bold),
        if (card.subtitle != null && card.subtitle!.isNotEmpty)
          buildWrappedCardSubtitle(
            card.subtitle!,
            textTheme.bodyMuted,
            padding: const EdgeInsets.only(top: 12),
          ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 18),
          _DetailChips(
            chips: chips,
            colorScheme: colorScheme,
            textTheme: textTheme,
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
}
