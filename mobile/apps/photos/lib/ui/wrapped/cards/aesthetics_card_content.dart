part of 'package:photos/ui/wrapped/wrapped_viewer_page.dart';

Widget? buildAestheticsCardContent(
  WrappedCard card,
  EnteColorScheme colorScheme,
  EnteTextTheme textTheme,
) {
  switch (card.type) {
    case WrappedCardType.blurryFaces:
      return _BlurryFacesCardContent(
        card: card,
        colorScheme: colorScheme,
        textTheme: textTheme,
      );
    case WrappedCardType.yearInColor:
      return _YearInColorCardContent(
        card: card,
        colorScheme: colorScheme,
        textTheme: textTheme,
      );
    case WrappedCardType.monochrome:
      return _MonochromeCardContent(
        card: card,
        colorScheme: colorScheme,
        textTheme: textTheme,
      );
    case WrappedCardType.top9Wow:
      return _TopWowCardContent(
        card: card,
        colorScheme: colorScheme,
        textTheme: textTheme,
      );
    default:
      return null;
  }
}

class _BlurryFacesCardContent extends StatelessWidget {
  const _BlurryFacesCardContent({
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
    final List<MediaRef> supportingMedia = card.media
        .skip(3)
        .take(2)
        .toList(growable: false);

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
        if (supportingMedia.isNotEmpty) ...[
          const SizedBox(height: 20),
          _MediaPairRow(
            media: supportingMedia,
            colorScheme: colorScheme,
            height: 132,
          ),
        ],
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 20),
          _DetailChips(
            chips: chips,
            colorScheme: colorScheme,
            textTheme: textTheme,
          ),
        ],
        const Spacer(),
      ],
    );
  }
}

class _YearInColorCardContent extends StatelessWidget {
  const _YearInColorCardContent({
    required this.card,
    required this.colorScheme,
    required this.textTheme,
  });

  final WrappedCard card;
  final EnteColorScheme colorScheme;
  final EnteTextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final List<String> detailChips = _stringListFromMeta(
      card.meta,
      "detailChips",
    );
    final List<_PaletteEntry> palette = _paletteEntriesFromMeta(card.meta);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MediaGrid(
          media: card.media.take(6).toList(growable: false),
          colorScheme: colorScheme,
        ),
        const SizedBox(height: 24),
        buildWrappedCardTitle(card.title, textTheme.h2Bold),
        if (card.subtitle != null && card.subtitle!.isNotEmpty)
          buildWrappedCardSubtitle(
            card.subtitle!,
            textTheme.bodyMuted,
            padding: const EdgeInsets.only(top: 12),
          ),
        if (palette.isNotEmpty) ...[
          const SizedBox(height: 18),
          _PaletteSwatches(
            entries: palette,
            colorScheme: colorScheme,
            textTheme: textTheme,
          ),
        ],
        if (detailChips.isNotEmpty) ...[
          const SizedBox(height: 20),
          _DetailChips(
            chips: detailChips,
            colorScheme: colorScheme,
            textTheme: textTheme,
          ),
        ],
        const Spacer(),
      ],
    );
  }
}

class _MonochromeCardContent extends StatelessWidget {
  const _MonochromeCardContent({
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildWrappedCardTitle(card.title, textTheme.h2Bold),
        if (card.subtitle != null && card.subtitle!.isNotEmpty)
          buildWrappedCardSubtitle(
            card.subtitle!,
            textTheme.bodyMuted,
            padding: const EdgeInsets.only(top: 12),
          ),
        const SizedBox(height: 20),
        _MediaGrid(
          media: card.media.take(6).toList(growable: false),
          colorScheme: colorScheme,
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 18),
          _DetailChips(
            chips: chips,
            colorScheme: colorScheme,
            textTheme: textTheme,
          ),
        ],
        const Spacer(),
      ],
    );
  }
}

class _TopWowCardContent extends StatelessWidget {
  const _TopWowCardContent({
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildWrappedCardTitle(card.title, textTheme.h2Bold),
        if (card.subtitle != null && card.subtitle!.isNotEmpty)
          buildWrappedCardSubtitle(
            card.subtitle!,
            textTheme.bodyMuted,
            padding: const EdgeInsets.only(top: 12),
          ),
        const SizedBox(height: 20),
        _MediaGrid(
          media: card.media.take(6).toList(growable: false),
          colorScheme: colorScheme,
        ),
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 18),
          _DetailChips(
            chips: chips,
            colorScheme: colorScheme,
            textTheme: textTheme,
          ),
        ],
        const Spacer(),
      ],
    );
  }
}

class _PaletteEntry {
  _PaletteEntry({required this.name, required this.hex, required this.count});

  final String name;
  final String hex;
  final int count;

  factory _PaletteEntry.fromJson(Map<String, Object?> json) {
    return _PaletteEntry(
      name: json["name"] as String? ?? "",
      hex: json["hex"] as String? ?? "",
      count: (json["count"] as num?)?.toInt() ?? 0,
    );
  }
}

List<_PaletteEntry> _paletteEntriesFromMeta(Map<String, Object?> meta) {
  final List<dynamic> raw =
      meta["palette"] as List<dynamic>? ?? const <dynamic>[];
  return raw
      .map(
        (dynamic entry) =>
            _PaletteEntry.fromJson((entry as Map).cast<String, Object?>()),
      )
      .where((_PaletteEntry entry) => entry.name.isNotEmpty)
      .toList(growable: false);
}

class _PaletteSwatches extends StatelessWidget {
  const _PaletteSwatches({
    required this.entries,
    required this.colorScheme,
    required this.textTheme,
  });

  final List<_PaletteEntry> entries;
  final EnteColorScheme colorScheme;
  final EnteTextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: entries
          .map((entry) => _buildSwatch(entry))
          .toList(growable: false),
    );
  }

  Widget _buildSwatch(_PaletteEntry entry) {
    final Color resolved = _colorFromHex(entry.hex, colorScheme.primary500);
    final Color swatchBackground = resolved.withValues(alpha: 0.16);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: swatchBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(color: resolved, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Text(
            entry.name,
            style: textTheme.smallMuted.copyWith(color: colorScheme.fillStrong),
          ),
        ],
      ),
    );
  }
}

Color _colorFromHex(String hex, Color fallback) {
  String sanitized = hex.trim();
  if (sanitized.startsWith("#")) {
    sanitized = sanitized.substring(1);
  }
  if (sanitized.length == 6) {
    sanitized = "FF$sanitized";
  }
  final int? value = int.tryParse(sanitized, radix: 16);
  if (value == null) {
    return fallback;
  }
  return Color(value);
}
