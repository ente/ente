import "dart:math" as math;
import "dart:ui" as ui;

import "package:ente_components/ente_components.dart";
import "package:figma_squircle/figma_squircle.dart";
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter/services.dart";
import "package:hugeicons/hugeicons.dart";
import "package:intl/intl.dart";
import "package:photos/core/constants.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/services/app_navigation_service.dart";
import "package:photos/ui/viewer/file/file_icons_widget.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";
import "package:photos/ui/viewer/gallery/state/gallery_files_inherited_widget.dart";

class AlbumCoverAppBar extends StatefulWidget {
  const AlbumCoverAppBar({
    super.key,
    required this.collection,
    required this.cover,
    required this.title,
    required this.actionsBuilder,
    required this.coverActions,
    required this.backgroundColor,
    required this.collapsedHeight,
    this.heroTag,
    this.bottom,
  });

  final Collection collection;
  final EnteFile cover;
  final String title;
  final List<Widget> Function(Color foregroundColor) actionsBuilder;
  final List<Widget> coverActions;
  final Color backgroundColor;
  final double collapsedHeight;
  final String? heroTag;
  final PreferredSizeWidget? bottom;

  static HeaderAppBarGeometry resolveGeometry(
    BuildContext context, {
    required double collapsedHeight,
    required double bottomHeight,
  }) {
    final topPadding = MediaQuery.paddingOf(context).top;
    return HeaderAppBarGeometry(
      minExtent: topPadding + collapsedHeight + bottomHeight,
      maxExtent: topPadding + _coverHeight + _coverBottomInset(bottomHeight),
    );
  }

  @override
  State<AlbumCoverAppBar> createState() => _AlbumCoverAppBarState();
}

class _AlbumCoverAppBarState extends State<AlbumCoverAppBar> with RouteAware {
  late SystemUiOverlayStyle _pinnedOverlayStyle;
  bool _isCovered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    _pinnedOverlayStyle = SystemUiOverlayStyle(
      statusBarIconBrightness: isDarkTheme ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDarkTheme ? Brightness.dark : Brightness.light,
    );
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      AppNavigationService.instance.routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPushNext() {
    setState(() => _isCovered = true);
  }

  @override
  void didPopNext() {
    GalleryFilesState.maybeOf(context)?.invalidateCaptureDateRange();
    setState(() => _isCovered = false);
  }

  @override
  void dispose() {
    AppNavigationService.instance.routeObserver.unsubscribe(this);
    SystemChrome.setSystemUIOverlayStyle(_pinnedOverlayStyle);
    WidgetsBinding.instance.scheduleFrame();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final bottomHeight = widget.bottom?.preferredSize.height ?? 0;
    final description = widget.collection.displayDescription;
    final animation = MediaQuery.disableAnimationsOf(context)
        ? kAlwaysCompleteAnimation
        : ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation;

    return SliverPersistentHeader(
      pinned: true,
      delegate: _AlbumCoverDelegate(
        geometry: AlbumCoverAppBar.resolveGeometry(
          context,
          collapsedHeight: widget.collapsedHeight,
          bottomHeight: bottomHeight,
        ),
        topPadding: MediaQuery.paddingOf(context).top,
        collapsedHeight: widget.collapsedHeight,
        bottomHeight: bottomHeight,
        colors: colors,
        backgroundColor: widget.backgroundColor,
        pinnedOverlayStyle: _pinnedOverlayStyle,
        isCovered: _isCovered,
        title: widget.title,
        actionsBuilder: widget.actionsBuilder,
        bottom: widget.bottom,
        photo: _CoverPhoto(
          cover: widget.cover,
          backgroundColor: widget.backgroundColor,
          heroTag: widget.heroTag,
          contentOpacity: animation,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CoverCaption(GalleryFilesState.maybeOf(context)?.captureDateRange),
            Semantics(
              header: true,
              child: Text(
                widget.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyles.display1.copyWith(color: colors.specialWhite),
              ),
            ),
            if (description != null) ...[
              const SizedBox(height: Spacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Text(
                  description,
                  maxLines: _descriptionMaxLines,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyles.mini.copyWith(
                    color: colors.specialWhite.withValues(alpha: 0.92),
                  ),
                ),
              ),
            ],
            if (widget.coverActions.isNotEmpty) ...[
              const SizedBox(height: _contentSpacing),
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: Spacing.md,
                children: widget.coverActions,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AlbumCoverActionButton extends StatelessWidget {
  const AlbumCoverActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final List<List<dynamic>> icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: _coverActionSize,
            height: _coverActionSize,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [_coverActionFillColor, _scrimColor],
              ),
            ),
            child: HugeIcon(
              icon: icon,
              size: IconSizes.small,
              color: context.componentColors.specialWhite,
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverPhoto extends StatelessWidget {
  const _CoverPhoto({
    required this.cover,
    required this.backgroundColor,
    this.heroTag,
    required this.contentOpacity,
  });

  final Animation<double> contentOpacity;
  final EnteFile cover;
  final Color backgroundColor;
  final String? heroTag;

  @override
  Widget build(BuildContext context) {
    final thumbnail = ThumbnailWidget(
      cover,
      rawThumbnail: true,
      thumbnailSize: thumbnailLargeSize,
      useRequestedThumbnailSizeForLocalCache: true,
      useCachedThumbnailAsPlaceholder: true,
    );
    final photo = Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        thumbnail,
        _CoverPhotoScrims(backgroundColor: backgroundColor),
      ],
    );
    if (heroTag == null) {
      return photo;
    }
    const motionCurve = Curves.easeInOut;
    return Hero(
      tag: heroTag!,
      curve: motionCurve,
      reverseCurve: motionCurve,
      transitionOnUserGestures: true,
      placeholderBuilder: (context, size, child) =>
          SizedBox.fromSize(size: size, child: child),
      flightShuttleBuilder:
          (
            flightContext,
            animation,
            flightDirection,
            fromHeroContext,
            toHeroContext,
          ) {
            final cardContext = flightDirection == HeroFlightDirection.push
                ? fromHeroContext
                : toHeroContext;
            final coverContext = flightDirection == HeroFlightDirection.push
                ? toHeroContext
                : fromHeroContext;
            var card = (cardContext.widget as Hero).child;
            if (card is SizedBox && card.child != null) {
              card = card.child!;
            }
            final SmoothBorderRadius cardRadius;
            if (card is ClipSmoothRect) {
              cardRadius = card.radius;
              card = card.child;
            } else if (card is ClipRRect) {
              final radius = card.borderRadius.resolve(
                Directionality.of(cardContext),
              );
              cardRadius = SmoothBorderRadius.only(
                topLeft: SmoothRadius(
                  cornerRadius: radius.topLeft.x,
                  cornerSmoothing: 0,
                ),
                topRight: SmoothRadius(
                  cornerRadius: radius.topRight.x,
                  cornerSmoothing: 0,
                ),
                bottomLeft: SmoothRadius(
                  cornerRadius: radius.bottomLeft.x,
                  cornerSmoothing: 0,
                ),
                bottomRight: SmoothRadius(
                  cornerRadius: radius.bottomRight.x,
                  cornerSmoothing: 0,
                ),
              );
              card = card.child!;
            } else {
              cardRadius = SmoothBorderRadius.zero;
            }
            final image =
                _heroImage(fromHeroContext) ?? _heroImage(cardContext);
            return _CoverHeroFlight(
              animation: (ModalRoute.of(coverContext)! as PageRoute).animation!
                  .drive(CurveTween(curve: motionCurve)),
              image: image?.image,
              contentOpacity: contentOpacity,
              card: card,
              showVideoIcon: cover.fileType == FileType.video,
              cardRadius: cardRadius,
              backgroundColor: backgroundColor,
            );
          },
      child: photo,
    );
  }
}

RenderImage? _heroImage(BuildContext context) {
  RenderImage? image;
  void visit(RenderObject renderObject) {
    if (renderObject is RenderImage && renderObject.image != null) {
      image ??= renderObject;
    } else if (image == null) {
      renderObject.visitChildren(visit);
    }
  }

  final renderObject = context.findRenderObject();
  if (renderObject != null) {
    visit(renderObject);
  }
  return image;
}

class _CoverHeroFlight extends StatefulWidget {
  const _CoverHeroFlight({
    required this.animation,
    required this.contentOpacity,
    required this.image,
    required this.card,
    required this.showVideoIcon,
    required this.cardRadius,
    required this.backgroundColor,
  });

  final Animation<double> animation;
  final Animation<double> contentOpacity;
  final ui.Image? image;
  final Widget card;
  final bool showVideoIcon;
  final SmoothBorderRadius cardRadius;
  final Color backgroundColor;

  @override
  State<_CoverHeroFlight> createState() => _CoverHeroFlightState();
}

class _CoverHeroFlightState extends State<_CoverHeroFlight> {
  late final ui.Image? _image = widget.image?.clone();

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: ReverseAnimation(widget.contentOpacity),
      child: AnimatedBuilder(
        animation: widget.animation,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_image != null)
              RawImage(image: _image, fit: BoxFit.cover)
            else
              widget.card,
            if (_image != null && widget.showVideoIcon)
              FadeTransition(
                opacity: ReverseAnimation(widget.animation),
                child: const VideoOverlayIcon(),
              ),
            FadeTransition(
              opacity: widget.animation,
              child: _CoverPhotoScrims(backgroundColor: widget.backgroundColor),
            ),
          ],
        ),
        builder: (context, child) => ClipSmoothRect(
          radius: SmoothBorderRadius.lerp(
            widget.cardRadius,
            SmoothBorderRadius.zero,
            widget.animation.value,
          )!,
          child: child!,
        ),
      ),
    );
  }
}

class _CoverPhotoScrims extends StatelessWidget {
  const _CoverPhotoScrims({required this.backgroundColor});

  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        const ColoredBox(color: _photoScrimColor),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: _coverDissolveHeight,
          child: CustomPaint(painter: _CoverDissolvePainter(backgroundColor)),
        ),
        Positioned(
          top:
              MediaQuery.paddingOf(context).top +
              _contentScrimTop -
              _contentScrimBlur * 2,
          left:
              (MediaQuery.sizeOf(context).width - _contentScrimWidth) / 2 -
              0.5 -
              _contentScrimBlur * 2,
          width: _contentScrimWidth + _contentScrimBlur * 4,
          height: _contentScrimHeight + _contentScrimBlur * 4,
          child: IgnorePointer(
            child: RepaintBoundary(
              child: ClipRect(
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: _contentScrimBlur,
                    sigmaY: _contentScrimBlur,
                  ),
                  child: const CustomPaint(
                    painter: _CoverContentScrimPainter(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CoverContentScrimPainter extends CustomPainter {
  const _CoverContentScrimPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(_contentScrimWidth / 2, _contentScrimHeight / 2);
    canvas.drawCircle(
      Offset.zero,
      1,
      Paint()
        ..shader = ui.Gradient.radial(Offset.zero, 1, const [
          Color.from(
            alpha: 0.24,
            red: 0.0585186,
            green: 0.0585186,
            blue: 0.0585186,
          ),
          Color.from(
            alpha: 0.096,
            red: 0.0224357,
            green: 0.0224357,
            blue: 0.0224357,
          ),
        ]),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CoverContentScrimPainter oldDelegate) => false;
}

class _CoverDissolvePainter extends CustomPainter {
  const _CoverDissolvePainter(this.backgroundColor);

  final Color backgroundColor;

  @override
  void paint(Canvas canvas, Size size) {
    final direction = Offset(
      0.0221519917 / size.width,
      0.9999704361 / size.height,
    );
    final center = size.center(Offset.zero);
    const centerPosition = 0.0221519917 / 2 + 0.9999704361 / 2 - 0.0110464599;
    final vector = direction / direction.distanceSquared;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          center - vector * centerPosition,
          center + vector * (1 - centerPosition),
          [backgroundColor.withValues(alpha: 0), backgroundColor],
        ),
    );
  }

  @override
  bool shouldRepaint(_CoverDissolvePainter oldDelegate) =>
      oldDelegate.backgroundColor != backgroundColor;
}

class _CoverCaption extends StatelessWidget {
  const _CoverCaption(this.dateRange);

  final ({int oldest, int newest})? dateRange;

  @override
  Widget build(BuildContext context) {
    final dateRange = this.dateRange;
    if (dateRange == null) {
      return const SizedBox.shrink();
    }
    final start = DateTime.fromMicrosecondsSinceEpoch(dateRange.oldest);
    final end = DateTime.fromMicrosecondsSinceEpoch(dateRange.newest);
    final locale = Localizations.localeOf(context).toString();
    final dayPattern = locale == "en"
        ? "d MMM y"
        : DateFormat.yMMMd(locale).pattern!;
    final monthDayPattern = locale == "en"
        ? "d MMM"
        : DateFormat.MMMd(locale).pattern!;
    final yearRange =
        "${DateFormat.y(locale).format(start)} – ${DateFormat.y(locale).format(end)}";
    final monthRange = start.year == end.year
        ? start.month == end.month
              ? DateFormat.yMMM(locale).format(end)
              : "${DateFormat.MMM(locale).format(start)} – ${DateFormat.yMMM(locale).format(end)}"
        : "${DateFormat.yMMM(locale).format(start)} – ${DateFormat.yMMM(locale).format(end)}";
    final String dayRange;
    if (start.year != end.year) {
      dayRange =
          "${DateFormat(dayPattern, locale).format(start)} – ${DateFormat(dayPattern, locale).format(end)}";
    } else if (start.month != end.month) {
      dayRange =
          "${DateFormat(monthDayPattern, locale).format(start)} – ${DateFormat(dayPattern, locale).format(end)}";
    } else if (start.day != end.day) {
      final days =
          "${NumberFormat("0", locale).format(start.day)}–${NumberFormat("0", locale).format(end.day)}";
      dayRange = DateFormat(
        dayPattern.replaceAllMapped(
          RegExp("('(?:[^']|'')*')|d+"),
          (match) => match.group(1) ?? "'$days'",
        ),
        locale,
      ).format(end);
    } else {
      dayRange = DateFormat(dayPattern, locale).format(end);
    }
    final captions = end.year - start.year >= 2
        ? [yearRange]
        : [dayRange, monthRange, yearRange];
    final style = TextStyles.tiny.copyWith(
      color: context.componentColors.specialWhite.withValues(alpha: 0.82),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final caption = captions.firstWhere((caption) {
          final painter = TextPainter(
            text: TextSpan(text: caption.toUpperCase(), style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: 1,
          )..layout();
          final fits = painter.width <= constraints.maxWidth - Spacing.md * 2;
          painter.dispose();
          return fits;
        }, orElse: () => captions.last);
        return Padding(
          padding: const EdgeInsets.only(bottom: _contentSpacing),
          child: Center(
            child: DecoratedBox(
              decoration: const ShapeDecoration(
                color: _captionFillColor,
                shape: StadiumBorder(),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.sm,
                ),
                child: Text(caption.toUpperCase(), maxLines: 1, style: style),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AlbumCoverDelegate extends SliverPersistentHeaderDelegate {
  const _AlbumCoverDelegate({
    required this.geometry,
    required this.topPadding,
    required this.collapsedHeight,
    required this.bottomHeight,
    required this.colors,
    required this.backgroundColor,
    required this.pinnedOverlayStyle,
    required this.isCovered,
    required this.title,
    required this.actionsBuilder,
    required this.bottom,
    required this.photo,
    required this.content,
  });

  final HeaderAppBarGeometry geometry;
  final double topPadding;
  final double collapsedHeight;
  final double bottomHeight;
  final ColorTokens colors;
  final Color backgroundColor;
  final SystemUiOverlayStyle pinnedOverlayStyle;
  final bool isCovered;
  final String title;
  final List<Widget> Function(Color foregroundColor) actionsBuilder;
  final PreferredSizeWidget? bottom;
  final Widget photo;
  final Widget content;

  @override
  double get maxExtent => geometry.maxExtent;

  @override
  double get minExtent => geometry.minExtent;

  @override
  OverScrollHeaderStretchConfiguration get stretchConfiguration =>
      _stretchConfiguration;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final collapseOffset = math.min(shrinkOffset, geometry.collapseExtent);
    final pinnedProgress =
        ((collapseOffset / geometry.collapseExtent - _pinnedFadeStart) /
                (1 - _pinnedFadeStart))
            .clamp(0.0, 1.0);
    final contentOpacity = (1 - collapseOffset / _contentFadeExtent).clamp(
      0.0,
      1.0,
    );
    final titleOpacity = (1 - contentOpacity * 2).clamp(0.0, 1.0);
    final foregroundColor = Color.lerp(
      colors.specialWhite,
      colors.textBase,
      ((pinnedProgress - _foregroundSwitchStart) /
              (_foregroundSwitchEnd - _foregroundSwitchStart))
          .clamp(0.0, 1.0),
    )!;
    final coverBottomInset = _coverBottomInset(bottomHeight);
    final respectRightInset = Theme.of(context).platform != TargetPlatform.iOS;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: pinnedProgress < 0.5 && !isCovered
          ? _coverOverlayStyle
          : pinnedOverlayStyle,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -collapseOffset,
            left: 0,
            right: 0,
            bottom: coverBottomInset - 1,
            child: HeroMode(enabled: collapseOffset == 0, child: photo),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topPadding + _topScrimHeight,
            child: const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_scrimColor, _transparentScrimColor],
                  ),
                ),
              ),
            ),
          ),
          if (contentOpacity > 0)
            Positioned(
              top: topPadding + collapsedHeight,
              left: Spacing.lg,
              right: Spacing.lg,
              bottom: coverBottomInset + collapsedHeight,
              child: SafeArea(
                top: false,
                bottom: false,
                child: LayoutBuilder(
                  builder: (context, constraints) => Opacity(
                    opacity: contentOpacity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        child: content,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (pinnedProgress > 0)
            Positioned.fill(
              child: ColoredBox(
                color: backgroundColor.withValues(alpha: pinnedProgress),
              ),
            ),
          Positioned(
            top:
                topPadding +
                (Spacing.lg -
                        (collapsedHeight - _compactHeaderControlSize) / 2) *
                    (1 - pinnedProgress),
            left: Spacing.lg,
            right: Spacing.lg,
            height: collapsedHeight,
            child: SafeArea(
              top: false,
              bottom: false,
              left: false,
              right: respectRightInset,
              child: Row(
                spacing: Spacing.md,
                children: [
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    icon: const Icon(Icons.arrow_back),
                    color: foregroundColor,
                    iconSize: IconSizes.medium,
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  Expanded(
                    child: ExcludeSemantics(
                      excluding: contentOpacity > 0,
                      child: Opacity(
                        opacity: titleOpacity,
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyles.display3.copyWith(
                            color: foregroundColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: _headerActionSpacing,
                    children: actionsBuilder(foregroundColor),
                  ),
                ],
              ),
            ),
          ),
          if (bottom != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: bottomHeight,
              child: SafeArea(
                top: false,
                bottom: false,
                left: false,
                right: respectRightInset,
                child: bottom!,
              ),
            ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _AlbumCoverDelegate oldDelegate) => true;
}

double _coverBottomInset(double bottomHeight) {
  return math.max(0.0, bottomHeight - _bottomOverlap);
}

const _coverHeight = 441.0;
const _coverDissolveHeight = 100.0;
const _topScrimHeight = 31.0;
const _bottomOverlap = 25.0;
const _contentSpacing = 22.0;
const _contentScrimTop = 146.0;
const _contentScrimWidth = 308.0;
const _contentScrimHeight = 157.0;
const _contentScrimBlur = 54.25;
const _compactHeaderControlSize = 38.0;
const _headerActionSpacing = 6.0;
const _contentFadeExtent = 120.0;
const _pinnedFadeStart = 0.6;
const _foregroundSwitchStart = 0.4;
const _foregroundSwitchEnd = 0.6;
const _descriptionMaxLines = 3;
const _coverActionSize = 42.0;

const _photoScrimColor = Color.from(alpha: 0.24, red: 0, green: 0, blue: 0);
const _scrimColor = Color(0x33000000);
const _transparentScrimColor = Color(0x00000000);
const _captionFillColor = Color.from(alpha: 0.32, red: 0, green: 0, blue: 0);
const _coverActionFillColor = Color(0x66000000);

const _coverOverlayStyle = SystemUiOverlayStyle(
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
);

final _stretchConfiguration = OverScrollHeaderStretchConfiguration();
