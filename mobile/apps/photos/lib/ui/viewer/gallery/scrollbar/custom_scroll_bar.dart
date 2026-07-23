import "dart:async";
import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/models/gallery/gallery_groups.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/viewer/gallery/component/group/type.dart";
import "package:photos/ui/viewer/gallery/scrollbar/scroll_bar_with_use_notifier.dart";
import "package:photos/utils/misc_util.dart";
import "package:photos/utils/widget_util.dart";

class CustomScrollBar extends StatefulWidget {
  final Widget child;
  final ValueNotifier<double> bottomPadding;
  final double topPadding;
  final ScrollController scrollController;
  final GalleryGroups galleryGroups;
  final ValueNotifier<bool> inUseNotifier;
  final double heighOfViewport;
  const CustomScrollBar({
    super.key,
    required this.child,
    required this.scrollController,
    required this.galleryGroups,
    required this.inUseNotifier,
    required this.heighOfViewport,
    required this.bottomPadding,
    required this.topPadding,
  });

  @override
  State<CustomScrollBar> createState() => _CustomScrollBarState();
}

class _CustomScrollBarState extends State<CustomScrollBar> {
  final _logger = Logger("CustomScrollBar2");
  final _scrollbarKey = GlobalKey();
  List<({double position, String title})>? positionToTitleMap;
  double? heightOfScrollbarDivider;
  double? heightOfScrollTrack;
  late bool _showScrollbarDivisions;
  late bool _showThumb;

  // Scrollbar's thumb height is not fixed by default. If the scrollable is short
  // enough, the scrollbar's height can go above the minimum length.
  // In our case, we only depend on this value for showing scrollbar divisions,
  // which we do not show unless scrollable is long enough. So we can safely
  // assume that the scrollbar's height will always this minimum value.
  static const _kScrollbarMinLength = 36.0;

  @override
  void initState() {
    super.initState();
    _init();
    widget.bottomPadding.addListener(_computePositionToTitleMap);
  }

  @override
  void didUpdateWidget(covariant CustomScrollBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _init();
  }

  @override
  void dispose() {
    widget.bottomPadding.removeListener(_computePositionToTitleMap);
    super.dispose();
  }

  void _init() {
    _logger.info("Initializing CustomScrollBar2");
    if (widget.galleryGroups.groupType.showScrollbarDivisions() &&
        widget.galleryGroups.groupLayouts.last.maxOffset >
            widget.heighOfViewport * 8) {
      _showScrollbarDivisions = true;
    } else {
      _showScrollbarDivisions = false;
    }

    if (widget.galleryGroups.groupLayouts.last.maxOffset >
        widget.heighOfViewport * 3) {
      _showThumb = true;
    } else {
      _showThumb = false;
    }

    if (_showScrollbarDivisions) {
      getIntrinsicSizeOfWidget(
        const ScrollBarDivider(title: "Temp"),
        context,
      ).then((size) {
        if (mounted) {
          setState(() {
            heightOfScrollbarDivider = size.height;
          });
        }

        // Reason for calling _computePositionToTileMap here is, it needs
        // heightOfScrollbarDivider to be set.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _computePositionToTitleMap();
        });
      });
    }
  }

  // Galleries where this scrollbar is used can gave different extents of headers
  // and footers. These extents are not taken into account while computing
  // the position of scrollbar divisions since we only show scrollbar divisions
  // if the scrollable is long enough, where the header and footer extents
  // are negligible compared to max extent of the scrollable.
  Future<void> _computePositionToTitleMap() async {
    _logger.info("Computing position to title map");
    final result = <({double position, String title})>[];
    heightOfScrollTrack = await _getHeightOfScrollTrack();
    if (!mounted ||
        heightOfScrollTrack == null ||
        heightOfScrollTrack! <= 0 ||
        heightOfScrollbarDivider == null) {
      return;
    }
    final maxScrollExtent = widget.scrollController.position.maxScrollExtent;
    if (maxScrollExtent <= 0) {
      return;
    }

    for (final scrollbarDivision in widget.galleryGroups.scrollbarDivisions) {
      final scrollOffsetOfGroup = widget
          .galleryGroups
          .groupIdToScrollOffsetMap[scrollbarDivision.groupID];
      if (scrollOffsetOfGroup == null) {
        continue;
      }

      final groupScrollOffsetToUse = scrollOffsetOfGroup - heightOfScrollTrack!;
      if (groupScrollOffsetToUse < 0) {
        result.add((position: 0, title: scrollbarDivision.title));
      } else {
        // By default, the exact scroll position of the scrollable isn't tied
        // to the center or one constant point of it's scrollbar. This point of
        // the scrollbar moves from top to bottom across it when the scrollable
        // is scolled from top to bottom.

        // This correction is to ensure that the scrollbar division elements
        // appear at the same point of the scrollbar everytime and are
        // accurate in terms of UX (that is, when scrollbar's is dragged to a
        // particular scrollbar division (start of the division in gallery),
        // the division element is always at the same point of the scrollbar).
        // Ideally this point should be the mid of the scrollbar, but it's
        // slightly off, not sure why. But this is fine enough.
        final fractionOfGroupScrollOffsetWrtMaxExtent =
            groupScrollOffsetToUse / maxScrollExtent;
        late final double positionCorrection;

        // This value is the distance from the mid of the scrollbar to the mid
        // of the scrollbar divider element when both pinned to the top, that
        // is, their top edges are overlapping.
        final value = (_kScrollbarMinLength - heightOfScrollbarDivider!) / 2;

        if (fractionOfGroupScrollOffsetWrtMaxExtent < 0.5) {
          positionCorrection =
              value * fractionOfGroupScrollOffsetWrtMaxExtent -
              (heightOfScrollbarDivider! *
                  fractionOfGroupScrollOffsetWrtMaxExtent);
        } else {
          positionCorrection =
              -value * fractionOfGroupScrollOffsetWrtMaxExtent -
              (heightOfScrollbarDivider! *
                  fractionOfGroupScrollOffsetWrtMaxExtent);
        }

        final adaptedPosition =
            heightOfScrollTrack! * fractionOfGroupScrollOffsetWrtMaxExtent +
            positionCorrection;

        result.add((position: adaptedPosition, title: scrollbarDivision.title));
      }
    }
    final filteredResult = <({double position, String title})>[];

    if (result.isEmpty) {
      return;
    }

    // Remove first scrollbar division since it doesn't add value in terms of UX
    result.removeAt(0);

    // Filter out positions that are too close to each other
    if (result.isNotEmpty) {
      filteredResult.add(result.first);
      for (int i = 1; i < result.length; i++) {
        if ((result[i].position - filteredResult.last.position).abs() >= 48) {
          filteredResult.add(result[i]);
        }
      }
    }
    if (mounted) {
      setState(() {
        positionToTitleMap = filteredResult;
      });
    }
  }

  Future<double> _getHeightOfScrollTrack() {
    final renderBox =
        _scrollbarKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return Future.value(0);
    }
    // Retry for : https://github.com/flutter/flutter/issues/25827
    return MiscUtil()
        .getNonZeroDoubleWithRetry(
          () => renderBox.size.height,
          id: "getHeightOfScrollTrack",
        )
        .then(
          (value) => value - widget.bottomPadding.value - widget.topPadding,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.centerLeft,
      children: [
        ScrollbarWithUseNotifer(
          key: _scrollbarKey,
          controller: widget.scrollController,
          interactive: true,
          inUseNotifier: widget.inUseNotifier,
          minScrollbarLength: _kScrollbarMinLength,
          showThumb: _showThumb,
          radius: const Radius.circular(4),
          thickness: 8,
          scrollbarPadding: EdgeInsets.only(
            bottom: widget.bottomPadding.value,
            top: widget.topPadding,
            right: 3,
          ),
          child: widget.child,
        ),
        positionToTitleMap == null || heightOfScrollbarDivider == null
            ? const SizedBox.shrink()
            : Padding(
                padding: EdgeInsets.only(
                  top: widget.topPadding,
                  bottom: widget.bottomPadding.value,
                ),
                child: ValueListenableBuilder<bool>(
                  valueListenable: widget.inUseNotifier,
                  builder: (context, inUse, _) {
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      switchInCurve: Curves.easeInOut,
                      switchOutCurve: Curves.easeInOut,
                      child: !inUse
                          ? const SizedBox.shrink()
                          : Stack(
                              clipBehavior: Clip.none,
                              children: positionToTitleMap!.map((record) {
                                return Positioned(
                                  top: record.position,
                                  right: 32,
                                  child: ScrollBarDivider(title: record.title),
                                );
                              }).toList(),
                            ),
                    );
                  },
                ),
              ),
      ],
    );
  }
}

class ScrollBarDivider extends StatelessWidget {
  final String title;
  const ScrollBarDivider({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final textTheme = getEnteTextTheme(context);
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.backgroundElevated2,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colorScheme.strokeFaint, width: 0.5),
        // TODO: Remove shadow if scrolling perf
        // is affected.
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Center(
        child: Text(title, style: textTheme.miniMuted, maxLines: 1),
      ),
    );
  }
}
