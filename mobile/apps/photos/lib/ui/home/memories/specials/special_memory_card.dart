import "dart:async";
import "dart:math";
import "dart:typed_data";

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:photos/core/constants.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/memories/special_memory.dart";
import "package:photos/module/download/thumbnail.dart";
import "package:photos/theme/colors.dart";
import "package:photos/ui/home/memories/memory_card_constants.dart";
import "package:photos/ui/home/memories/specials/one_day_overlay.dart";
import "package:photos/ui/home/memories/specials/special_memory_chrome.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

class SpecialMemoryCard extends StatelessWidget {
  final SpecialMemory memory;
  final VoidCallback onTap;
  final double width;
  final double height;

  const SpecialMemoryCard({
    required this.memory,
    required this.width,
    required this.height,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final memory = this.memory;
    if (!memory.isShowable) return const SizedBox.shrink();
    final isSeen = memory.memories.every((item) => item.isSeen());
    final opensInStoryViewer = memory is OneDayMemory;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kMemoryCardStripGap / 2.0,
      ),
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(kMemoryCardBorderRadius),
          child: Container(
            height: height,
            width: width,
            foregroundDecoration: isSeen
                ? const BoxDecoration(
                    color: Color(0xFFBFBFBF),
                    backgroundBlendMode: BlendMode.saturation,
                  )
                : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                switch (memory) {
                  ThenAndNowMemory() => _ThenAndNowCover(memory),
                  YearInAFlashMemory() => _YearInAFlashCover(memory),
                  OneDayMemory() => _OneDayCover(memory),
                },
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, Color(0xB8000000)],
                      stops: [0.53663, 0.89955],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Hero(
                      tag: opensInStoryViewer
                          ? memory.title
                          : specialMemoryTitleHeroTag(memory.id),
                      child: Text(
                        memory.title,
                        maxLines: 3,
                        style: TextStyle(
                          fontSize: 14,
                          height: 16 / 14,
                          fontFamily: TextStyles.outfitFontFamily,
                          package: TextStyles.fontPackage,
                          color: isSeen ? textFaintDark : Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0,
                        ),
                        textAlign: TextAlign.left,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  final EnteFile file;

  const _Cover(this.file);

  @override
  Widget build(BuildContext context) {
    return ThumbnailWidget(
      file,
      shouldShowSyncStatus: false,
      shouldShowFavoriteIcon: false,
      shouldShowVideoOverlayIcon: false,
      thumbnailSize: thumbnailLargeSize,
      key: Key("special-memory-${file.tag}"),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;

  const _Chip(this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0x8C000000),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(label, style: specialDisplayStyle(12).copyWith(height: 1.3)),
    );
  }
}

class _ThenAndNowCover extends StatefulWidget {
  final ThenAndNowMemory memory;

  const _ThenAndNowCover(this.memory);

  @override
  State<_ThenAndNowCover> createState() => _ThenAndNowCoverState();
}

class _ThenAndNowCoverState extends State<_ThenAndNowCover>
    with SingleTickerProviderStateMixin {
  static const _sways = 8;

  late final _sway = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  )..repeat(reverse: true, count: _sways);
  late final EnteFile _then = widget.memory.then.file;
  late final EnteFile _now = widget.memory.now.file;

  @override
  void dispose() {
    _sway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final memory = widget.memory;
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Stack(
          fit: StackFit.expand,
          children: [
            _Cover(_now),
            AnimatedBuilder(
              animation: _sway,
              child: _Cover(_then),
              builder: (context, child) {
                final split =
                    0.36 + 0.28 * Curves.easeInOut.transform(_sway.value);
                final x = split * size.width;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRect(clipper: LeftPartClipper(split), child: child),
                    Positioned(
                      left: x - 1,
                      top: 0,
                      bottom: 0,
                      width: 2,
                      child: const ColoredBox(color: Colors.white),
                    ),
                    Positioned(
                      left: x - 11,
                      top: size.height * 0.42 - 11,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const RotatedBox(
                          quarterTurns: 1,
                          child: Icon(
                            Icons.unfold_more_rounded,
                            size: 16,
                            color: SpecialMemoryColors.ink,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            Positioned(left: 8, top: 8, child: _Chip("${memory.thenYear}")),
            Positioned(right: 8, top: 8, child: _Chip("${memory.nowYear}")),
          ],
        );
      },
    );
  }
}

class _YearInAFlashCover extends StatefulWidget {
  final YearInAFlashMemory memory;

  const _YearInAFlashCover(this.memory);

  @override
  State<_YearInAFlashCover> createState() => _YearInAFlashCoverState();
}

class _YearInAFlashCoverState extends State<_YearInAFlashCover>
    with SingleTickerProviderStateMixin {
  static const _frameCount = 12;
  static const _frameDuration = Duration(milliseconds: 420);
  static const _flips = 4;

  late final AnimationController _flip;
  final List<({EnteFile file, Uint8List thumbnail})> _frames = [];
  int? _shown;

  @override
  void initState() {
    super.initState();
    _flip = AnimationController(vsync: this)..addListener(_showCurrentFrame);
    unawaited(_load());
  }

  @override
  void dispose() {
    _flip.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final photos = List.of(widget.memory.memories);
    final count = min(_frameCount, photos.length);
    for (var index = 0; index < count; index++) {
      final file = photos[index * photos.length ~/ count].file;
      final thumbnail = await _thumbnailOf(file);
      if (!mounted) return;
      if (thumbnail != null && _isInMemory(file)) {
        _frames.add((file: file, thumbnail: thumbnail));
      }
    }
    if (_frames.length < 2) return;
    unawaited(
      _flip.repeat(period: _frameDuration * _frames.length, count: _flips),
    );
  }

  Future<Uint8List?> _thumbnailOf(EnteFile file) async {
    try {
      return await getThumbnail(file);
    } catch (_) {
      return null;
    }
  }

  bool _isInMemory(EnteFile file) {
    return widget.memory.memories.any((photo) => photo.file == file);
  }

  void _showCurrentFrame() {
    final shown = _flip.isAnimating
        ? (_flip.value * _frames.length).floor() % _frames.length
        : null;
    if (shown != _shown) setState(() => _shown = shown);
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.memory.memories;
    final cover = photos.firstOrNull;
    if (cover == null) return const SizedBox.shrink();
    final shown = _shown;
    final frame = shown == null ? null : _frames[shown];
    return Stack(
      fit: StackFit.expand,
      children: [
        _Cover(cover.file),
        if (frame != null && _isInMemory(frame.file))
          Image.memory(
            frame.thumbnail,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            cacheWidth: thumbnailLargeSize,
          ),
        const Positioned(
          left: 8,
          top: 8,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0x8C000000),
              shape: BoxShape.circle,
            ),
            child: Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.fast_forward_rounded,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OneDayCover extends StatelessWidget {
  final OneDayMemory memory;

  const _OneDayCover(this.memory);

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final first = wallClockOf(memory.memories.first.file);
    final last = wallClockOf(memory.memories.last.file);
    final clock = DateFormat.jm(locale);
    return Stack(
      fit: StackFit.expand,
      children: [
        Hero(
          tag: "memories${memory.memories.first.file.tag}",
          child: _Cover(memory.memories.first.file),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0x8C000000), Colors.transparent],
              stops: [0, 0.4],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          top: 10,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(
                height: 30,
                width: double.infinity,
                child: CustomPaint(painter: SunArcGlyphPainter()),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  "${clock.format(first)} – ${clock.format(last)}",
                  style: specialDisplayStyle(11).copyWith(height: 1.3),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
