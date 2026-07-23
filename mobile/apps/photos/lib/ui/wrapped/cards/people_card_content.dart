part of 'package:photos/ui/wrapped/wrapped_viewer_page.dart';

Widget? buildPeopleCardContent(
  WrappedCard card,
  EnteColorScheme colorScheme,
  EnteTextTheme textTheme,
) {
  switch (card.type) {
    case WrappedCardType.topPerson:
      return _TopPersonCardContent(
        card: card,
        colorScheme: colorScheme,
        textTheme: textTheme,
      );
    case WrappedCardType.topThreePeople:
      return _TopThreePeopleCardContent(
        card: card,
        colorScheme: colorScheme,
        textTheme: textTheme,
      );
    case WrappedCardType.groupVsSolo:
      return _GroupVsSoloCardContent(
        card: card,
        colorScheme: colorScheme,
        textTheme: textTheme,
      );
    case WrappedCardType.newFaces:
      return _NewFacesCardContent(
        card: card,
        colorScheme: colorScheme,
        textTheme: textTheme,
      );
    default:
      return null;
  }
}

class _TopPersonCardContent extends StatelessWidget {
  const _TopPersonCardContent({
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

class _TopThreePeopleCardContent extends StatelessWidget {
  const _TopThreePeopleCardContent({
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
    final List<MediaRef> gridMedia = card.media.take(4).toList(growable: false);

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
        if (gridMedia.isNotEmpty) ...[
          const SizedBox(height: 24),
          _SquareMediaGrid(media: gridMedia, colorScheme: colorScheme),
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

class _GroupVsSoloCardContent extends StatelessWidget {
  const _GroupVsSoloCardContent({
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
    final List<MediaRef> collageMedia = card.media
        .take(5)
        .toList(growable: false);

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
        if (collageMedia.isNotEmpty) ...[
          const SizedBox(height: 20),
          _GroupSoloMediaCollage(media: collageMedia, colorScheme: colorScheme),
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

class _NewFacesCardContent extends StatelessWidget {
  const _NewFacesCardContent({
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
