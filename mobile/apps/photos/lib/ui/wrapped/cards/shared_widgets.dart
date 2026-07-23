part of 'package:photos/ui/wrapped/wrapped_viewer_page.dart';

Widget buildWrappedCardTitle(
  String text,
  TextStyle style, {
  EdgeInsetsGeometry? padding,
}) {
  final TextStyle titleStyle = style.copyWith(
    fontWeight: FontWeight.w700,
    letterSpacing: -2,
  );
  return _buildCenteredCardText(
    text: text,
    style: titleStyle,
    padding: padding,
  );
}

Widget buildWrappedCardSubtitle(
  String text,
  TextStyle style, {
  EdgeInsetsGeometry? padding,
}) {
  return _buildCenteredCardText(text: text, style: style, padding: padding);
}

Widget _buildCenteredCardText({
  required String text,
  required TextStyle style,
  EdgeInsetsGeometry? padding,
}) {
  final Widget label = Align(
    alignment: Alignment.center,
    child: Text(text, style: style, textAlign: TextAlign.center),
  );
  if (padding != null) {
    return Padding(padding: padding, child: label);
  }
  return label;
}

Widget _mediaTileOrPlaceholder(
  MediaRef? ref,
  EnteColorScheme colorScheme, {
  double borderRadius = 20,
  double? aspectRatio,
}) {
  if (ref == null) {
    Widget placeholder = _MediaPlaceholder(
      colorScheme: colorScheme,
      borderRadius: borderRadius,
    );
    if (aspectRatio != null) {
      placeholder = AspectRatio(aspectRatio: aspectRatio, child: placeholder);
    }
    return placeholder;
  }
  return _MediaTile(
    mediaRef: ref,
    borderRadius: borderRadius,
    aspectRatio: aspectRatio,
  );
}

class _DetailChips extends StatelessWidget {
  const _DetailChips({
    required this.chips,
    required this.colorScheme,
    required this.textTheme,
  });

  final List<String> chips;
  final EnteColorScheme colorScheme;
  final EnteTextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.center,
        runAlignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: chips
            .map(
              (String chip) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.fillFaint,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  chip,
                  style: textTheme.smallMuted.copyWith(
                    color: textTheme.smallMuted.color ?? colorScheme.fillMuted,
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _HeroMediaCollage extends StatelessWidget {
  const _HeroMediaCollage({required this.media, required this.colorScheme});

  final List<MediaRef> media;
  final EnteColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) {
      return _MediaPlaceholder(
        height: 220,
        colorScheme: colorScheme,
        borderRadius: 24,
      );
    }

    final List<MediaRef> trimmed = media.take(3).toList(growable: false);
    final MediaRef primary = trimmed.first;
    final List<MediaRef> side = trimmed.skip(1).toList(growable: false);

    return SizedBox(
      height: 220,
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: _MediaTile(
              mediaRef: primary,
              borderRadius: 24,
              aspectRatio: 3 / 4,
            ),
          ),
          if (side.isNotEmpty) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: List<Widget>.generate(2, (int index) {
                  final MediaRef? ref = index < side.length
                      ? side[index]
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
          ],
        ],
      ),
    );
  }
}

class _MediaGrid extends StatelessWidget {
  const _MediaGrid({required this.media, required this.colorScheme});

  final List<MediaRef> media;
  final EnteColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) {
      return _MediaPlaceholder(height: 200, colorScheme: colorScheme);
    }
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: Column(
        children: List<Widget>.generate(3, (int row) {
          return Expanded(
            child: Row(
              children: List<Widget>.generate(2, (int column) {
                final int index = row * 2 + column;
                final MediaRef? ref = index < media.length
                    ? media[index]
                    : null;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: column == 1 ? 0 : 10,
                      bottom: row == 2 ? 0 : 10,
                    ),
                    child: ref != null
                        ? _MediaTile(mediaRef: ref, borderRadius: 16)
                        : _MediaPlaceholder(
                            colorScheme: colorScheme,
                            borderRadius: 16,
                          ),
                  ),
                );
              }),
            ),
          );
        }),
      ),
    );
  }
}

class _SquareMediaGrid extends StatelessWidget {
  const _SquareMediaGrid({required this.media, required this.colorScheme});

  static const int _kCrossAxisCount = 2;
  static const double _kSpacing = 12;

  final List<MediaRef> media;
  final EnteColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) {
      return _MediaPlaceholder(
        colorScheme: colorScheme,
        borderRadius: 20,
        height: 120,
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double availableWidth =
            constraints.hasBoundedWidth &&
                constraints.maxWidth.isFinite &&
                constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;
        final double rawTileSize =
            (availableWidth - _kSpacing * (_kCrossAxisCount - 1)) /
            _kCrossAxisCount;
        final double tileSize = rawTileSize.isFinite && rawTileSize > 0
            ? rawTileSize
            : 140;

        return Wrap(
          spacing: _kSpacing,
          runSpacing: _kSpacing,
          children: media
              .map(
                (MediaRef ref) => SizedBox(
                  width: tileSize,
                  height: tileSize,
                  child: _mediaTileOrPlaceholder(
                    ref,
                    colorScheme,
                    borderRadius: 20,
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _MediaPairRow extends StatelessWidget {
  const _MediaPairRow({
    required this.media,
    required this.colorScheme,
    this.height,
  });

  final List<MediaRef> media;
  final EnteColorScheme colorScheme;
  final double? height;
  static const double _kBorderRadius = 20;

  @override
  Widget build(BuildContext context) {
    final List<MediaRef?> slots = <MediaRef?>[
      media.isNotEmpty ? media.first : null,
      media.length > 1 ? media[1] : null,
    ];
    Widget row = Row(
      children: [
        for (final (int index, MediaRef? ref) in slots.indexed) ...[
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: index == slots.length - 1 ? 0 : 12,
              ),
              child: _mediaTileOrPlaceholder(
                ref,
                colorScheme,
                borderRadius: _kBorderRadius,
              ),
            ),
          ),
        ],
      ],
    );
    if (height != null) {
      row = SizedBox(height: height, child: row);
    }
    return row;
  }
}

class _GroupSoloMediaCollage extends StatelessWidget {
  const _GroupSoloMediaCollage({
    required this.media,
    required this.colorScheme,
  });

  final List<MediaRef> media;
  final EnteColorScheme colorScheme;

  MediaRef? _at(int index) => index < media.length ? media[index] : null;

  @override
  Widget build(BuildContext context) {
    if (media.isEmpty) {
      return _MediaPlaceholder(
        height: 200,
        colorScheme: colorScheme,
        borderRadius: 24,
      );
    }

    final MediaRef? primary = _at(0);
    final MediaRef? rightTop = _at(1);
    final MediaRef? rightBottom = _at(2);
    final MediaRef? bottomLeft = _at(3);
    final MediaRef? bottomRight = _at(4);

    final List<MediaRef> bottomMedia = <MediaRef>[?bottomLeft, ?bottomRight];

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: Row(
            children: [
              Expanded(
                flex: (rightTop != null || rightBottom != null) ? 3 : 1,
                child: _mediaTileOrPlaceholder(
                  primary,
                  colorScheme,
                  borderRadius: 24,
                ),
              ),
              if (rightTop != null || rightBottom != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Column(
                      children: [
                        Expanded(
                          child: _mediaTileOrPlaceholder(
                            rightTop,
                            colorScheme,
                            borderRadius: 22,
                          ),
                        ),
                        if (rightTop != null && rightBottom != null)
                          const SizedBox(height: 12),
                        if (rightBottom != null)
                          Expanded(
                            child: _mediaTileOrPlaceholder(
                              rightBottom,
                              colorScheme,
                              borderRadius: 22,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (bottomMedia.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildBottomRow(bottomMedia, colorScheme),
        ],
      ],
    );
  }

  Widget _buildBottomRow(List<MediaRef> refs, EnteColorScheme colorScheme) {
    if (refs.length == 1) {
      return SizedBox(
        height: 120,
        child: Align(
          alignment: Alignment.center,
          child: FractionallySizedBox(
            widthFactor: 0.65,
            child: _mediaTileOrPlaceholder(
              refs.first,
              colorScheme,
              borderRadius: 22,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: 110,
      child: Row(
        children: [
          Expanded(
            child: _mediaTileOrPlaceholder(
              refs[0],
              colorScheme,
              borderRadius: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _mediaTileOrPlaceholder(
              refs[1],
              colorScheme,
              borderRadius: 22,
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  const _MediaTile({
    required this.mediaRef,
    required this.borderRadius,
    this.aspectRatio,
  });

  final MediaRef mediaRef;
  final double borderRadius;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox.expand(child: _MediaThumb(ref: mediaRef)),
    );
    if (aspectRatio != null) {
      content = AspectRatio(aspectRatio: aspectRatio!, child: content);
    }
    return _MediaPreviewGesture(mediaRef: mediaRef, child: content);
  }
}

class _MediaPreviewGesture extends StatelessWidget {
  const _MediaPreviewGesture({required this.mediaRef, required this.child});

  final MediaRef mediaRef;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final _MediaPreviewController? controller = _MediaPreviewController.maybeOf(
      context,
    );
    if (controller == null) {
      return child;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => controller.onPreviewTapDown(),
      onTap: () => controller.onPreviewStart(mediaRef),
      onTapCancel: controller.onPreviewTapCancel,
      child: child,
    );
  }
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({
    required this.colorScheme,
    this.height,
    this.borderRadius = 20,
  });

  final EnteColorScheme colorScheme;
  final double? height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final Widget child = Container(
      decoration: BoxDecoration(
        color: colorScheme.primary400.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
    if (height != null) {
      return SizedBox(height: height, child: child);
    }
    return child;
  }
}

class _MediaThumb extends StatefulWidget {
  const _MediaThumb({required this.ref});

  final MediaRef ref;

  @override
  State<_MediaThumb> createState() => _MediaThumbState();
}

class _MediaThumbState extends State<_MediaThumb> {
  late Future<EnteFile?> _fileFuture;

  @override
  void initState() {
    super.initState();
    _fileFuture = _ensureFile();
  }

  @override
  void didUpdateWidget(covariant _MediaThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ref.uploadedFileID != widget.ref.uploadedFileID) {
      _fileFuture = _ensureFile();
    }
  }

  Future<EnteFile?> _ensureFile() {
    return WrappedMediaPreloader.instance.ensureFile(widget.ref.uploadedFileID);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final EnteFile? cached = WrappedMediaPreloader.instance.getCachedFile(
      widget.ref.uploadedFileID,
    );
    if (cached != null) {
      return _buildThumbnail(cached);
    }
    return FutureBuilder<EnteFile?>(
      future: _fileFuture,
      builder: (BuildContext context, AsyncSnapshot<EnteFile?> snapshot) {
        final EnteFile? file = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done && file == null) {
          return Container(color: colorScheme.fillFaint);
        }
        if (file == null) {
          return Container(color: colorScheme.fillFaint);
        }
        return _buildThumbnail(file);
      },
    );
  }

  Widget _buildThumbnail(EnteFile file) {
    return ThumbnailWidget(
      file,
      fit: BoxFit.cover,
      rawThumbnail: true,
      shouldShowSyncStatus: false,
      shouldShowOwnerAvatar: false,
      shouldShowFavoriteIcon: false,
      shouldShowVideoDuration: false,
      shouldShowVideoOverlayIcon: false,
    );
  }
}

Color _heatmapColorForValue(int value, int maxValue, EnteColorScheme scheme) {
  if (value <= 0 || maxValue <= 0) {
    return scheme.fillFaint;
  }
  final double t = (value / maxValue).clamp(0.0, 1.0);
  return Color.lerp(
        scheme.primary400.withValues(alpha: 0.25),
        scheme.primary500,
        t,
      ) ??
      scheme.primary500;
}

List<String> _stringListFromMeta(Map<String, Object?> meta, String key) {
  final Object? raw = meta[key];
  if (raw is List) {
    return raw.whereType<String>().toList(growable: false);
  }
  return const <String>[];
}

class _StoryProgressBar extends StatelessWidget {
  const _StoryProgressBar({
    required this.progressValues,
    required this.colorScheme,
  });

  final List<double> progressValues;
  final EnteColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final Color trackColor = Colors.white.withValues(alpha: 0.22);
    final Color fillColor = Colors.white.withValues(alpha: 0.92);
    return Row(
      children: [
        for (final (int index, double value)
            in progressValues.indexed) ...<Widget>[
          Expanded(
            child: _ProgressSegment(
              progress: value,
              trackColor: trackColor,
              fillColor: fillColor,
            ),
          ),
          if (index != progressValues.length - 1) const SizedBox(width: 6),
        ],
      ],
    );
  }
}

class _ProgressSegment extends StatelessWidget {
  const _ProgressSegment({
    required this.progress,
    required this.trackColor,
    required this.fillColor,
  });

  final double progress;
  final Color trackColor;
  final Color fillColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        children: [
          Container(height: 4, color: trackColor),
          FractionallySizedBox(
            widthFactor: progress.clamp(0.0, 1.0),
            child: Container(height: 4, color: fillColor),
          ),
        ],
      ),
    );
  }
}
