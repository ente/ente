part of 'package:photos/ui/wrapped/wrapped_viewer_page.dart';

typedef _CardContentBuilder =
    Widget? Function(
      WrappedCard card,
      EnteColorScheme colorScheme,
      EnteTextTheme textTheme,
    );

final List<_CardContentBuilder> _cardContentBuilders = <_CardContentBuilder>[
  buildStatsCardContent,
  buildPeopleCardContent,
  buildPlacesCardContent,
  buildAestheticsCardContent,
  buildCurationCardContent,
  buildNarrativeCardContent,
  buildBadgeCardContent,
  buildBadgeDebugCardContent,
];

// Boost saturation so blurred backgrounds stay vibrant while we overlay gradients.
const List<double> _kSaturationBoostMatrix = <double>[
  1.27559,
  -0.25032,
  -0.02527,
  0,
  0,
  -0.07441,
  1.09968,
  -0.02527,
  0,
  0,
  -0.07441,
  -0.25032,
  1.32473,
  0,
  0,
  0,
  0,
  0,
  1,
  0,
];

class _StoryCard extends StatelessWidget {
  const _StoryCard({
    required this.card,
    required this.colorScheme,
    required this.textTheme,
    required this.isActive,
    required this.gradientVariantIndex,
  });

  final WrappedCard card;
  final EnteColorScheme colorScheme;
  final EnteTextTheme textTheme;
  final bool isActive;
  final int gradientVariantIndex;

  @override
  Widget build(BuildContext context) {
    final bool isBadge =
        card.type == WrappedCardType.badge ||
        card.type == WrappedCardType.badgeDebug;
    final bool showMeshGradient = _shouldApplyMeshGradient(card);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isActive ? 1.0 : 0.6,
      child: Padding(
        padding: _kStoryCardOuterPadding,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              return FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomCenter,
                child: _StoryDesignSurface(
                  isBadge: isBadge,
                  showMeshGradient: showMeshGradient,
                  gradientVariantIndex: gradientVariantIndex,
                  card: card,
                  colorScheme: colorScheme,
                  textTheme: textTheme,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

bool _shouldApplyMeshGradient(WrappedCard card) {
  switch (card.type) {
    case WrappedCardType.badge:
    case WrappedCardType.badgeDebug:
    case WrappedCardType.yearInColor:
    case WrappedCardType.monochrome:
      return false;
    default:
      return true;
  }
}

class _MeshGradientOverlay extends StatelessWidget {
  const _MeshGradientOverlay({required this.variantIndex});

  final int variantIndex;

  static const List<Color> _palette = <Color>[
    Color(0xFF43D681),
    Color(0xFFF0FF03),
    Color(0xFF0E9297),
    Color(0xFFA0FFBF),
  ];

  static final List<MeshGradientPoint> _points = <MeshGradientPoint>[
    MeshGradientPoint(position: const Offset(-0.3, 0.2), color: _palette[0]),
    MeshGradientPoint(position: const Offset(0.2, -0.2), color: _palette[1]),
    MeshGradientPoint(position: const Offset(0.9, 0.5), color: _palette[2]),
    MeshGradientPoint(position: const Offset(0.4, 1.2), color: _palette[3]),
  ];

  static const List<_MeshGradientVariant> _variants = <_MeshGradientVariant>[
    _MeshGradientVariant(horizontalFactor: -1, verticalFactor: -1),
    _MeshGradientVariant(horizontalFactor: 1, verticalFactor: -1),
    _MeshGradientVariant(horizontalFactor: 1, verticalFactor: 1),
    _MeshGradientVariant(horizontalFactor: -1, verticalFactor: 1),
  ];

  static final MeshGradientOptions _options = MeshGradientOptions(
    blend: 3.4,
    noiseIntensity: 0.08,
  );

  static const double _kCanvasScale = 3.0;
  static const double _kTranslationSafetyFactor = 0.94;

  @override
  Widget build(BuildContext context) {
    final _MeshGradientVariant variant =
        _variants[variantIndex % _variants.length];
    const double maxTranslation =
        ((_kCanvasScale - 1.0) / (2 * _kCanvasScale)) *
        _kTranslationSafetyFactor;
    final Offset translation = Offset(
      variant.horizontalFactor * maxTranslation,
      variant.verticalFactor * maxTranslation,
    );
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double width = constraints.maxWidth;
          final double height = constraints.maxHeight;
          final double canvasWidth = width * _kCanvasScale;
          final double canvasHeight = height * _kCanvasScale;
          return OverflowBox(
            alignment: Alignment.center,
            minWidth: canvasWidth,
            minHeight: canvasHeight,
            maxWidth: canvasWidth,
            maxHeight: canvasHeight,
            child: FractionalTranslation(
              translation: translation,
              child: Opacity(
                opacity: 0.62,
                child: MeshGradient(points: _points, options: _options),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MeshGradientVariant {
  const _MeshGradientVariant({
    required this.horizontalFactor,
    required this.verticalFactor,
  });

  final double horizontalFactor;
  final double verticalFactor;
}

class _StoryCardBackground extends StatelessWidget {
  const _StoryCardBackground({required this.card, required this.colorScheme});

  final WrappedCard card;
  final EnteColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    if (card.media.isEmpty) {
      return Container(color: colorScheme.backgroundElevated);
    }
    final MediaRef primary = card.media.first;
    if (primary.uploadedFileID <= 0) {
      return Container(color: colorScheme.backgroundElevated);
    }
    return _BlurredMediaBackground(mediaRef: primary, colorScheme: colorScheme);
  }
}

class _BlurredMediaBackground extends StatefulWidget {
  const _BlurredMediaBackground({
    required this.mediaRef,
    required this.colorScheme,
  });

  final MediaRef mediaRef;
  final EnteColorScheme colorScheme;

  @override
  State<_BlurredMediaBackground> createState() =>
      _BlurredMediaBackgroundState();
}

class _BlurredMediaBackgroundState extends State<_BlurredMediaBackground> {
  late Future<EnteFile?> _fileFuture;

  @override
  void initState() {
    super.initState();
    _fileFuture = _ensureFile();
  }

  @override
  void didUpdateWidget(covariant _BlurredMediaBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaRef.uploadedFileID != widget.mediaRef.uploadedFileID) {
      _fileFuture = _ensureFile();
    }
  }

  Future<EnteFile?> _ensureFile() {
    return WrappedMediaPreloader.instance.ensureFile(
      widget.mediaRef.uploadedFileID,
    );
  }

  @override
  Widget build(BuildContext context) {
    final EnteFile? cached = WrappedMediaPreloader.instance.getCachedFile(
      widget.mediaRef.uploadedFileID,
    );
    if (cached != null) {
      return _buildBackground(cached);
    }
    return FutureBuilder<EnteFile?>(
      future: _fileFuture,
      builder: (BuildContext context, AsyncSnapshot<EnteFile?> snapshot) {
        final EnteFile? file = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting &&
            file == null) {
          return _buildPlaceholder();
        }
        if (file == null) {
          return _buildPlaceholder();
        }
        return _buildBackground(file);
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(color: widget.colorScheme.backgroundElevated);
  }

  Widget _buildBackground(EnteFile file) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColorFiltered(
            colorFilter: const ColorFilter.matrix(_kSaturationBoostMatrix),
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 36, sigmaY: 36),
              child: ThumbnailWidget(
                file,
                fit: BoxFit.cover,
                rawThumbnail: true,
                shouldShowSyncStatus: false,
                shouldShowOwnerAvatar: false,
                shouldShowFavoriteIcon: false,
                shouldShowVideoDuration: false,
                shouldShowVideoOverlayIcon: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardContent extends StatelessWidget {
  const _CardContent({
    required this.card,
    required this.colorScheme,
    required this.textTheme,
  });

  final WrappedCard card;
  final EnteColorScheme colorScheme;
  final EnteTextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    for (final _CardContentBuilder builder in _cardContentBuilders) {
      final Widget? built = builder(card, colorScheme, textTheme);
      if (built != null) {
        return built;
      }
    }
    return _GenericCardContent(card: card, textTheme: textTheme);
  }
}

class _GenericCardContent extends StatelessWidget {
  const _GenericCardContent({required this.card, required this.textTheme});

  final WrappedCard card;
  final EnteTextTheme textTheme;

  @override
  Widget build(BuildContext context) {
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
        const Spacer(),
      ],
    );
  }
}

class _StoryDesignSurface extends StatelessWidget {
  const _StoryDesignSurface({
    required this.isBadge,
    required this.showMeshGradient,
    required this.gradientVariantIndex,
    required this.card,
    required this.colorScheme,
    required this.textTheme,
  });

  final bool isBadge;
  final bool showMeshGradient;
  final int gradientVariantIndex;
  final WrappedCard card;
  final EnteColorScheme colorScheme;
  final EnteTextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kStoryDesignWidth,
      height: _kStoryDesignHeight + _kStoryControlReserveHeight,
      child: isBadge
          ? Column(
              children: [
                Expanded(
                  child: _CardContent(
                    card: card,
                    colorScheme: colorScheme,
                    textTheme: textTheme,
                  ),
                ),
                const SizedBox(
                  height:
                      _kStoryControlReserveHeight - _kStoryControlBottomPadding,
                ),
                const SizedBox(height: _kStoryControlBottomPadding),
              ],
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _StoryCardBackground(card: card, colorScheme: colorScheme),
                  if (showMeshGradient)
                    _MeshGradientOverlay(variantIndex: gradientVariantIndex),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            colorScheme.backgroundElevated.withValues(
                              alpha: 0.45,
                            ),
                            colorScheme.backgroundElevated.withValues(
                              alpha: 0.2,
                            ),
                            colorScheme.backgroundElevated.withValues(
                              alpha: 0.08,
                            ),
                          ],
                          stops: const <double>[0.0, 0.6, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Column(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: _kStoryCardInnerPadding,
                            child: _CardContent(
                              card: card,
                              colorScheme: colorScheme,
                              textTheme: textTheme,
                            ),
                          ),
                        ),
                        const SizedBox(
                          height:
                              _kStoryControlReserveHeight -
                              _kStoryControlBottomPadding,
                        ),
                        const SizedBox(height: _kStoryControlBottomPadding),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
