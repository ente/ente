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
  final double viewportHeight;
  const CustomScrollBar({
    super.key,
    required this.child,
    required this.scrollController,
    required this.galleryGroups,
    required this.inUseNotifier,
    required this.viewportHeight,
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

  // Divisions only appear in long galleries, where the thumb stays at this
  // minimum height.
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
    final supportsScrollbarDivisions = widget.galleryGroups.groupType
        .showScrollbarDivisions();
    final maxOffset =
        widget.galleryGroups.groupLayouts.lastOrNull?.maxOffset ?? 0.0;

    _showScrollbarDivisions =
        supportsScrollbarDivisions && maxOffset > widget.viewportHeight * 8;

    _showThumb = maxOffset > widget.viewportHeight * 3;

    if (!_showScrollbarDivisions) return;

    getIntrinsicSizeOfWidget(
      const ScrollBarDivider(title: "Temp"),
      context,
    ).then((size) {
      if (mounted) {
        setState(() {
          heightOfScrollbarDivider = size.height;
        });
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _computePositionToTitleMap();
      });
    });
  }

  // Division positions ignore header and footer heights. They are negligible
  // in the long galleries that show divisions.
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
        // Account for the thumb's height so each label lines up with its
        // gallery section while dragging.
        final fractionOfGroupScrollOffsetWrtMaxExtent =
            groupScrollOffsetToUse / maxScrollExtent;
        late final double positionCorrection;

        // Offset between the thumb and label centers at the top.
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

    // The first division marks the top and adds no useful landmark.
    result.removeAt(0);

    // Keep division labels at least 48 pixels apart.
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
    // RenderBox height may initially be zero:
    // https://github.com/flutter/flutter/issues/25827
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
