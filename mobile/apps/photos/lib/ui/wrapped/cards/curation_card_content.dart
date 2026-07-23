part of 'package:photos/ui/wrapped/wrapped_viewer_page.dart';

Widget? buildCurationCardContent(
  WrappedCard card,
  EnteColorScheme colorScheme,
  EnteTextTheme textTheme,
) {
  switch (card.type) {
    case WrappedCardType.favorites:
      return _FavoritesCardContent(
        card: card,
        colorScheme: colorScheme,
        textTheme: textTheme,
      );
    default:
      return null;
  }
}

class _FavoritesCardContent extends StatefulWidget {
  const _FavoritesCardContent({
    required this.card,
    required this.colorScheme,
    required this.textTheme,
  });

  final WrappedCard card;
  final EnteColorScheme colorScheme;
  final EnteTextTheme textTheme;

  @override
  State<_FavoritesCardContent> createState() => _FavoritesCardContentState();
}

class _FavoritesCardContentState extends State<_FavoritesCardContent> {
  static const int _kDefaultRotationMillis = 2400;

  late List<List<MediaRef>> _groups;
  int _groupIndex = 0;
  int _rotationMillis = _kDefaultRotationMillis;
  Timer? _rotationTimer;

  @override
  void initState() {
    super.initState();
    _configureFromCard();
  }

  @override
  void didUpdateWidget(covariant _FavoritesCardContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card != widget.card) {
      _configureFromCard();
    }
  }

  @override
  void dispose() {
    _rotationTimer?.cancel();
    super.dispose();
  }

  void _configureFromCard() {
    _rotationTimer?.cancel();
    _groups = _extractGroups(widget.card);
    _groupIndex = 0;

    final Object? rawRotation = widget.card.meta["rotationMillis"];
    final int? rotation = rawRotation is num ? rawRotation.toInt() : null;
    _rotationMillis = ((rotation ?? _kDefaultRotationMillis).clamp(
      1200,
      6000,
    )).toInt();

    if (_groups.length > 1) {
      _rotationTimer = Timer.periodic(
        Duration(milliseconds: _rotationMillis),
        (_) => _advanceGallery(),
      );
    }
  }

  void _advanceGallery() {
    if (!mounted || _groups.isEmpty) {
      return;
    }
    setState(() {
      _groupIndex = (_groupIndex + 1) % _groups.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final List<String> detailChips = _stringListFromMeta(
      widget.card.meta,
      "detailChips",
    );
    final List<MediaRef> currentMedia = _groups.isEmpty
        ? const <MediaRef>[]
        : _groups[_groupIndex.clamp(0, _groups.length - 1)];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildWrappedCardTitle(widget.card.title, widget.textTheme.h2Bold),
        if (widget.card.subtitle != null && widget.card.subtitle!.isNotEmpty)
          buildWrappedCardSubtitle(
            widget.card.subtitle!,
            widget.textTheme.bodyMuted,
            padding: const EdgeInsets.only(top: 12),
          ),
        const SizedBox(height: 22),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: KeyedSubtree(
            key: ValueKey<int>(_groupIndex),
            child: _MediaGrid(
              media: currentMedia,
              colorScheme: widget.colorScheme,
            ),
          ),
        ),
        if (detailChips.isNotEmpty) ...[
          const SizedBox(height: 18),
          _DetailChips(
            chips: detailChips,
            colorScheme: widget.colorScheme,
            textTheme: widget.textTheme,
          ),
        ],
        const Spacer(),
      ],
    );
  }

  List<List<MediaRef>> _extractGroups(WrappedCard card) {
    final Object? rawGroups = card.meta["galleryGroups"];
    if (rawGroups is List) {
      final List<List<MediaRef>> parsed = rawGroups
          .whereType<List>()
          .map(
            (List<dynamic> group) => group
                .whereType<num>()
                .map((num value) => value.toInt())
                .where((int id) => id > 0)
                .map(MediaRef.new)
                .toList(growable: false),
          )
          .where((List<MediaRef> group) => group.isNotEmpty)
          .toList(growable: false);
      if (parsed.isNotEmpty) {
        return parsed;
      }
    }

    if (card.media.isNotEmpty) {
      return <List<MediaRef>>[card.media.toList(growable: false)];
    }

    return const <List<MediaRef>>[<MediaRef>[]];
  }
}
