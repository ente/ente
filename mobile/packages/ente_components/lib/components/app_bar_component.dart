import 'dart:math' as math;
import 'dart:ui';

import 'package:ente_components/components/tooltip_component.dart';
import 'package:ente_components/theme/colors.dart';
import 'package:ente_components/theme/icon_sizes.dart';
import 'package:ente_components/theme/spacing.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';

typedef HeaderAppBarTitleBuilder =
    Widget Function(BuildContext context, HeaderAppBarTitleState state);

class HeaderAppBarTitleState {
  const HeaderAppBarTitleState({
    required this.title,
    required this.textStyle,
    required this.height,
  });

  final String title;
  final TextStyle textStyle;
  final double height;
}

/// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=11439-5036&m=dev
/// Section: Appbar/header / Header v2
/// Specs: Scroll view with a pinned header app bar that animates between
/// expanded and collapsed states.
///
/// Use this for normal screens. It owns the scroll view, adds the pinned header,
/// and provides enough scroll extent for short content to collapse cleanly.
class AppBarComponent extends StatefulWidget {
  const AppBarComponent({
    super.key,
    required this.title,
    required this.slivers,
    this.titleBuilder,
    this.titleBuilderHeight,
    this.onTitleTap,
    this.onTitleDoubleTap,
    this.onTitleLongPress,
    this.disableTitleTapReveal = false,
    this.subtitle,
    this.leading,
    this.backButton,
    this.onBack,
    this.actions = const [],
    this.bottom,
    this.expandedHeight,
    this.collapsedHeight = _defaultCollapsedHeight,
    this.horizontalPadding = Spacing.lg,
    this.backgroundColor,
    this.showExpandedBackButton = true,
    this.controller,
    this.physics,
    this.cacheExtent,
  });

  final String title;
  final HeaderAppBarTitleBuilder? titleBuilder;
  final double? titleBuilderHeight;
  final VoidCallback? onTitleTap;
  final VoidCallback? onTitleDoubleTap;
  final VoidCallback? onTitleLongPress;
  final bool disableTitleTapReveal;
  final String? subtitle;
  final Widget? leading;
  final Widget? backButton;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;
  final double? expandedHeight;
  final double collapsedHeight;
  final double horizontalPadding;
  final Color? backgroundColor;
  final bool showExpandedBackButton;
  final List<Widget> slivers;
  final ScrollController? controller;
  final ScrollPhysics? physics;
  final double? cacheExtent;

  @override
  State<AppBarComponent> createState() => _AppBarComponentState();
}

class _AppBarComponentState extends State<AppBarComponent> {
  ScrollController? _internalController;
  ScrollPosition? _scrollPosition;
  double _collapseExtent = 0;
  bool _isSnapping = false;
  bool _snapQueued = false;

  ScrollController get _controller =>
      widget.controller ?? (_internalController ??= ScrollController());

  @override
  void dispose() {
    _scrollPosition?.isScrollingNotifier.removeListener(_handleScrollActivity);
    _internalController?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AppBarComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _scrollPosition?.isScrollingNotifier.removeListener(
        _handleScrollActivity,
      );
      _scrollPosition = null;
      _internalController?.dispose();
      _internalController = null;
      _queueScrollPositionSync();
    }
  }

  void _queueScrollPositionSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncScrollPosition();
      }
    });
  }

  void _syncScrollPosition() {
    if (!_controller.hasClients) {
      return;
    }

    final position = _controller.position;
    if (identical(_scrollPosition, position)) {
      return;
    }

    _scrollPosition?.isScrollingNotifier.removeListener(_handleScrollActivity);
    _scrollPosition = position;
    _scrollPosition?.isScrollingNotifier.addListener(_handleScrollActivity);
  }

  void _handleScrollActivity() {
    final position = _scrollPosition;
    if (position == null || _isSnapping || !position.hasPixels) {
      return;
    }

    if (!position.isScrollingNotifier.value) {
      _settleHeader(position);
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0 || _isSnapping) {
      return false;
    }

    if (notification is ScrollEndNotification) {
      _settleHeader(notification.metrics);
    }

    return false;
  }

  void _settleHeader(ScrollMetrics metrics) {
    if (_collapseExtent <= _headerSnapTolerance) {
      return;
    }

    final pixels = metrics.pixels;
    if (pixels <= _headerSnapTolerance || pixels >= _collapseExtent) {
      return;
    }

    _queueSnapHeader(_collapseExtent);
  }

  void _queueSnapHeader(double target) {
    if (_snapQueued) {
      return;
    }

    _snapQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _snapQueued = false;
      if (mounted) {
        _snapHeader(target);
      }
    });
  }

  Future<void> _snapHeader(double target) async {
    if (!_controller.hasClients) {
      return;
    }

    _isSnapping = true;
    try {
      await _controller.animateTo(
        target.clamp(0.0, _controller.position.maxScrollExtent),
        duration: _headerSnapDuration,
        curve: Curves.easeOutCubic,
      );
    } finally {
      _isSnapping = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final metrics = _resolveHeaderAppBarMetrics(
      context,
      subtitle: widget.subtitle,
      expandedHeight: widget.expandedHeight,
      collapsedHeight: widget.collapsedHeight,
      titleBuilderHeight: widget.titleBuilderHeight,
    );
    _collapseExtent = metrics.collapseExtent;
    if (!_controller.hasClients ||
        !identical(_scrollPosition, _controller.position)) {
      _queueScrollPositionSync();
    }

    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: CustomScrollView(
        controller: _controller,
        physics: widget.physics,
        cacheExtent: widget.cacheExtent,
        slivers: [
          SliverAppBarComponent(
            title: widget.title,
            titleBuilder: widget.titleBuilder,
            titleBuilderHeight: widget.titleBuilderHeight,
            onTitleTap: widget.onTitleTap,
            onTitleDoubleTap: widget.onTitleDoubleTap,
            onTitleLongPress: widget.onTitleLongPress,
            disableTitleTapReveal: widget.disableTitleTapReveal,
            subtitle: widget.subtitle,
            leading: widget.leading,
            backButton: widget.backButton,
            onBack: widget.onBack,
            actions: widget.actions,
            bottom: widget.bottom,
            expandedHeight: widget.expandedHeight,
            collapsedHeight: widget.collapsedHeight,
            horizontalPadding: widget.horizontalPadding,
            backgroundColor: widget.backgroundColor ?? colors.backgroundBase,
            showExpandedBackButton: widget.showExpandedBackButton,
          ),
          ...widget.slivers,
          _AppBarCollapseSpacer(collapseExtent: metrics.collapseExtent),
        ],
      ),
    );
  }
}

class _AppBarCollapseSpacer extends StatelessWidget {
  const _AppBarCollapseSpacer({required this.collapseExtent});

  final double collapseExtent;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final fillerExtent = math.max(
          0.0,
          constraints.viewportMainAxisExtent +
              collapseExtent -
              constraints.precedingScrollExtent,
        );

        return SliverToBoxAdapter(child: SizedBox(height: fillerExtent));
      },
    );
  }
}

/// Low-level sliver for custom scroll compositions.
///
/// Prefer [AppBarComponent] for normal screens so short content gets the
/// correct collapse extent and settle behavior automatically.
class SliverAppBarComponent extends StatelessWidget {
  const SliverAppBarComponent({
    super.key,
    required this.title,
    this.titleBuilder,
    this.titleBuilderHeight,
    this.onTitleTap,
    this.onTitleDoubleTap,
    this.onTitleLongPress,
    this.disableTitleTapReveal = false,
    this.subtitle,
    this.leading,
    this.backButton,
    this.onBack,
    this.actions = const [],
    this.bottom,
    this.expandedHeight,
    this.collapsedHeight = _defaultCollapsedHeight,
    this.horizontalPadding = Spacing.lg,
    this.backgroundColor,
    this.showExpandedBackButton = true,
  });

  final String title;
  final HeaderAppBarTitleBuilder? titleBuilder;
  final double? titleBuilderHeight;
  final VoidCallback? onTitleTap;
  final VoidCallback? onTitleDoubleTap;
  final VoidCallback? onTitleLongPress;
  final bool disableTitleTapReveal;
  final String? subtitle;
  final Widget? leading;
  final Widget? backButton;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;
  final double? expandedHeight;
  final double collapsedHeight;
  final double horizontalPadding;
  final Color? backgroundColor;
  final bool showExpandedBackButton;

  static HeaderAppBarGeometry resolveGeometry(
    BuildContext context, {
    String? subtitle,
    double? expandedHeight,
    double collapsedHeight = _defaultCollapsedHeight,
    double? titleBuilderHeight,
    double bottomHeight = 0,
  }) {
    final metrics = _resolveHeaderAppBarMetrics(
      context,
      subtitle: subtitle,
      expandedHeight: expandedHeight,
      collapsedHeight: collapsedHeight,
      titleBuilderHeight: titleBuilderHeight,
    );
    final topPadding = MediaQuery.paddingOf(context).top;
    return HeaderAppBarGeometry(
      minExtent: topPadding + metrics.collapsedHeight + bottomHeight,
      maxExtent: topPadding + metrics.expandedHeight + bottomHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final metrics = _resolveHeaderAppBarMetrics(
      context,
      subtitle: subtitle,
      expandedHeight: expandedHeight,
      collapsedHeight: collapsedHeight,
      titleBuilderHeight: titleBuilderHeight,
    );

    return SliverPersistentHeader(
      pinned: true,
      delegate: _HeaderAppBarDelegate(
        title: title,
        titleBuilder: titleBuilder,
        titleBuilderHeight: titleBuilderHeight,
        onTitleTap: onTitleTap,
        onTitleDoubleTap: onTitleDoubleTap,
        onTitleLongPress: onTitleLongPress,
        disableTitleTapReveal: disableTitleTapReveal,
        subtitle: subtitle,
        leading: leading,
        backButton: backButton,
        onBack: onBack,
        actions: actions,
        bottom: bottom,
        bottomHeight: bottom?.preferredSize.height ?? 0,
        expandedHeight: metrics.expandedHeight,
        collapsedHeight: metrics.collapsedHeight,
        horizontalPadding: horizontalPadding,
        topPadding: MediaQuery.paddingOf(context).top,
        backgroundColor: backgroundColor,
        colors: colors,
        showExpandedBackButton: showExpandedBackButton,
        expandedTitleLineHeight: metrics.expandedTitleLineHeight,
        collapsedTitleLineHeight: metrics.collapsedTitleLineHeight,
        subtitleLineHeight: metrics.subtitleLineHeight,
      ),
    );
  }
}

class _HeaderAppBarDelegate extends SliverPersistentHeaderDelegate {
  const _HeaderAppBarDelegate({
    required this.title,
    required this.titleBuilder,
    required this.titleBuilderHeight,
    required this.onTitleTap,
    required this.onTitleDoubleTap,
    required this.onTitleLongPress,
    required this.disableTitleTapReveal,
    required this.subtitle,
    required this.leading,
    required this.backButton,
    required this.onBack,
    required this.actions,
    required this.bottom,
    required this.bottomHeight,
    required this.expandedHeight,
    required this.collapsedHeight,
    required this.horizontalPadding,
    required this.topPadding,
    required this.backgroundColor,
    required this.colors,
    required this.showExpandedBackButton,
    required this.expandedTitleLineHeight,
    required this.collapsedTitleLineHeight,
    required this.subtitleLineHeight,
  });

  final String title;
  final HeaderAppBarTitleBuilder? titleBuilder;
  final double? titleBuilderHeight;
  final VoidCallback? onTitleTap;
  final VoidCallback? onTitleDoubleTap;
  final VoidCallback? onTitleLongPress;
  final bool disableTitleTapReveal;
  final String? subtitle;
  final Widget? leading;
  final Widget? backButton;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;
  final double bottomHeight;
  final double expandedHeight;
  final double collapsedHeight;
  final double horizontalPadding;
  final double topPadding;
  final Color? backgroundColor;
  final ColorTokens colors;
  final bool showExpandedBackButton;
  final double expandedTitleLineHeight;
  final double collapsedTitleLineHeight;
  final double subtitleLineHeight;

  @override
  double get maxExtent => topPadding + expandedHeight + bottomHeight;

  @override
  double get minExtent => topPadding + collapsedHeight + bottomHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final scrollRange = maxExtent - minExtent;
    final progress = scrollRange == 0
        ? 1.0
        : (shrinkOffset / scrollRange).clamp(0.0, 1.0);
    final titleProgress = Curves.easeInOut.transform(progress);
    final expandedTitleHeight = titleBuilderHeight ?? expandedTitleLineHeight;
    final collapsedTitleHeight = titleBuilderHeight ?? collapsedTitleLineHeight;
    final titleLayoutHeight = titleBuilderHeight == null
        ? lerpDouble(expandedTitleHeight, collapsedTitleHeight, titleProgress)!
        : titleBuilderHeight!;
    final collapsedControlTop = _centeredTop(
      collapsedHeight,
      _headerControlSize,
    );
    final collapsedTitleTop = _centeredTop(
      collapsedHeight,
      collapsedTitleHeight,
    );
    final expandedTextBlockHeight =
        expandedTitleHeight +
        (subtitle == null ? 0 : _subtitleGap + subtitleLineHeight);
    final expandedContentTop =
        _expandedContentTop +
        math.min(
          subtitle == null ? 0.0 : subtitleLineHeight,
          math.max(0.0, collapsedHeight - expandedTitleHeight),
        );
    final leadingTop =
        expandedContentTop +
        _centerOffset(expandedTextBlockHeight, _headerControlSize);
    final actionsTop = lerpDouble(
      leadingTop,
      collapsedControlTop,
      titleProgress,
    )!;
    final collapsedTitleLeft = _collapsedLeadingWidth(backButton) + Spacing.md;
    final titleLeft = lerpDouble(
      leading == null ? 0 : _headerControlSize + Spacing.md,
      showExpandedBackButton ? collapsedTitleLeft : 0,
      titleProgress,
    )!;
    final titleTop = lerpDouble(
      expandedContentTop,
      collapsedTitleTop,
      titleProgress,
    )!;
    final titleRight = actions.isEmpty
        ? 0.0
        : _actionsWidth(actions.length) + Spacing.md;
    final leadingOpacity = 1 - titleProgress;
    final isLeadingHidden = leadingOpacity <= 0.01;

    return ColoredBox(
      color: backgroundColor ?? colors.backgroundBase,
      child: Padding(
        padding: EdgeInsets.only(top: topPadding),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              bottom: bottomHeight,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (leading != null)
                      Positioned(
                        left: 0,
                        top: leadingTop,
                        child: IgnorePointer(
                          ignoring: isLeadingHidden,
                          child: ExcludeSemantics(
                            excluding: isLeadingHidden,
                            child: Opacity(
                              opacity: leadingOpacity,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: SizedBox.square(
                                  dimension: _headerControlSize,
                                  child: leading,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    _MovingHeaderTitle(
                      title: title,
                      titleBuilder: titleBuilder,
                      onTap: onTitleTap,
                      onDoubleTap: onTitleDoubleTap,
                      onLongPress: onTitleLongPress,
                      disableTapReveal: disableTitleTapReveal,
                      top: titleTop,
                      left: titleLeft,
                      right: titleRight,
                      progress: titleProgress,
                      height: titleLayoutHeight,
                    ),
                    if (subtitle != null)
                      Positioned(
                        left: titleLeft,
                        right: titleRight,
                        top:
                            expandedContentTop +
                            expandedTitleHeight +
                            _subtitleGap,
                        child: IgnorePointer(
                          child: ExcludeSemantics(
                            child: Opacity(
                              opacity: 1 - titleProgress,
                              child: Text(
                                subtitle!,
                                maxLines: _subtitleMaxLines,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyles.mini.copyWith(
                                  color: colors.textLight,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _PinnedHeaderChrome(
                        backButton: backButton,
                        onBack: onBack,
                        actions: actions,
                        actionsTop: actionsTop,
                        chromeHeight: collapsedHeight,
                        showBackButton: showExpandedBackButton,
                      ),
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
                child: bottom!,
              ),
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _HeaderAppBarDelegate oldDelegate) {
    return oldDelegate.title != title ||
        titleBuilder != null ||
        oldDelegate.titleBuilder != null ||
        oldDelegate.titleBuilderHeight != titleBuilderHeight ||
        oldDelegate.onTitleTap != onTitleTap ||
        oldDelegate.onTitleDoubleTap != onTitleDoubleTap ||
        oldDelegate.onTitleLongPress != onTitleLongPress ||
        oldDelegate.disableTitleTapReveal != disableTitleTapReveal ||
        oldDelegate.subtitle != subtitle ||
        oldDelegate.leading != leading ||
        oldDelegate.backButton != backButton ||
        oldDelegate.onBack != onBack ||
        oldDelegate.actions != actions ||
        oldDelegate.bottom != bottom ||
        oldDelegate.bottomHeight != bottomHeight ||
        oldDelegate.expandedHeight != expandedHeight ||
        oldDelegate.collapsedHeight != collapsedHeight ||
        oldDelegate.horizontalPadding != horizontalPadding ||
        oldDelegate.topPadding != topPadding ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.colors != colors ||
        oldDelegate.showExpandedBackButton != showExpandedBackButton ||
        oldDelegate.expandedTitleLineHeight != expandedTitleLineHeight ||
        oldDelegate.collapsedTitleLineHeight != collapsedTitleLineHeight ||
        oldDelegate.subtitleLineHeight != subtitleLineHeight;
  }
}

class _PinnedHeaderChrome extends StatelessWidget {
  const _PinnedHeaderChrome({
    required this.backButton,
    required this.onBack,
    required this.actions,
    required this.actionsTop,
    required this.chromeHeight,
    required this.showBackButton,
  });

  final Widget? backButton;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final double actionsTop;
  final double chromeHeight;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (showBackButton)
          Align(
            alignment: Alignment.topLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _HeaderAppBarBackButton(
                  backButton: backButton,
                  onBack: onBack,
                  height: chromeHeight,
                ),
                const SizedBox(width: Spacing.md),
              ],
            ),
          ),
        if (actions.isNotEmpty)
          Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: EdgeInsets.only(top: actionsTop),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: _headerControlSize,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < actions.length; index++) ...[
                      SizedBox.square(
                        dimension: _headerControlSize,
                        child: Center(child: actions[index]),
                      ),
                      if (index != actions.length - 1)
                        const SizedBox(width: _headerControlGap),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HeaderAppBarBackButton extends StatelessWidget {
  const _HeaderAppBarBackButton({
    required this.backButton,
    required this.onBack,
    required this.height,
  });

  final Widget? backButton;
  final VoidCallback? onBack;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final tooltip = MaterialLocalizations.of(context).backButtonTooltip;

    return SizedBox(
      width: backButton == null ? _defaultBackIconSize : _headerControlSize,
      height: height,
      child: Align(
        alignment: Alignment.centerLeft,
        child: backButton == null
            ? Semantics(
                button: true,
                label: tooltip,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onBack ?? () => Navigator.maybePop(context),
                  child: SizedBox.square(
                    dimension: _defaultBackIconSize,
                    child: Icon(
                      Icons.arrow_back,
                      color: colors.textBase,
                      size: _defaultBackIconSize,
                    ),
                  ),
                ),
              )
            : SizedBox.square(
                dimension: _headerControlSize,
                child: Center(child: backButton),
              ),
      ),
    );
  }
}

const _headerControlSize = 38.0;
const _headerControlGap = Spacing.sm;
const _defaultBackIconSize = IconSizes.medium;
const _defaultCollapsedHeight = 56.0;
const _titleOnlyExpandedHeight = 92.0;
const _subtitleExpandedHeight = 110.0;
const _expandedContentTop = 48.0;
const _expandedContentBottomGap = Spacing.lg;
const _subtitleGap = 2.0;
const _subtitleMaxLines = 2;
const _headerSnapTolerance = 1.0;
const _headerSnapDuration = Duration(milliseconds: 160);
const _titleTooltipShowDuration = Duration(seconds: 3);

class HeaderAppBarGeometry {
  const HeaderAppBarGeometry({
    required this.minExtent,
    required this.maxExtent,
  });

  final double minExtent;
  final double maxExtent;

  double get collapseExtent => maxExtent - minExtent;
}

class _HeaderAppBarMetrics {
  const _HeaderAppBarMetrics({
    required this.expandedHeight,
    required this.collapsedHeight,
    required this.expandedTitleLineHeight,
    required this.collapsedTitleLineHeight,
    required this.subtitleLineHeight,
  });

  final double expandedHeight;
  final double collapsedHeight;
  final double expandedTitleLineHeight;
  final double collapsedTitleLineHeight;
  final double subtitleLineHeight;

  double get collapseExtent => expandedHeight - collapsedHeight;
}

_HeaderAppBarMetrics _resolveHeaderAppBarMetrics(
  BuildContext context, {
  required String? subtitle,
  required double? expandedHeight,
  required double collapsedHeight,
  required double? titleBuilderHeight,
}) {
  final textScaler = MediaQuery.textScalerOf(context);
  final expandedTitleLineHeight = _scaledLineHeight(
    textScaler,
    TextStyles.display2,
  );
  final collapsedTitleLineHeight = _scaledLineHeight(
    textScaler,
    TextStyles.display3,
  );
  final subtitleLineHeight = _scaledLineHeight(textScaler, TextStyles.mini);
  final subtitleHeight = subtitle == null
      ? 0.0
      : subtitleLineHeight * _subtitleMaxLines;
  final defaultExpandedHeight = subtitle == null
      ? _titleOnlyExpandedHeight
      : _subtitleExpandedHeight;
  final effectiveCollapsedHeight = _maxDouble(
    collapsedHeight,
    _maxDouble(
      _headerControlSize,
      _maxDouble(collapsedTitleLineHeight, titleBuilderHeight ?? 0),
    ),
  );
  final expandedTextBlockHeight =
      expandedTitleLineHeight +
      (subtitle == null ? 0 : _subtitleGap + subtitleHeight);
  final effectiveExpandedHeight = _maxDouble(
    expandedHeight ?? defaultExpandedHeight,
    _expandedContentTop +
        _maxDouble(expandedTextBlockHeight, _headerControlSize) +
        _expandedContentBottomGap,
  );

  return _HeaderAppBarMetrics(
    expandedHeight: effectiveExpandedHeight,
    collapsedHeight: effectiveCollapsedHeight,
    expandedTitleLineHeight: expandedTitleLineHeight,
    collapsedTitleLineHeight: collapsedTitleLineHeight,
    subtitleLineHeight: subtitleLineHeight,
  );
}

double _collapsedLeadingWidth(Widget? backButton) {
  return backButton == null ? _defaultBackIconSize : _headerControlSize;
}

double _centeredTop(double containerHeight, double childHeight) {
  return ((containerHeight - childHeight) / 2)
      .clamp(0.0, double.infinity)
      .toDouble();
}

double _centerOffset(double containerHeight, double childHeight) {
  return (containerHeight - childHeight) / 2;
}

double _maxDouble(double first, double second) {
  return first > second ? first : second;
}

double _scaledLineHeight(TextScaler textScaler, TextStyle style) {
  final fontSize = style.fontSize ?? 14;
  final height = style.height ?? 1;
  return textScaler.scale(fontSize) * height;
}

double _actionsWidth(int actionCount) {
  return (actionCount * _headerControlSize) +
      ((actionCount - 1) * _headerControlGap).clamp(0, double.infinity);
}

class _MovingHeaderTitle extends StatelessWidget {
  const _MovingHeaderTitle({
    required this.title,
    required this.titleBuilder,
    required this.onTap,
    required this.onDoubleTap,
    required this.onLongPress,
    required this.disableTapReveal,
    required this.top,
    required this.left,
    required this.right,
    required this.progress,
    required this.height,
  });

  final String title;
  final HeaderAppBarTitleBuilder? titleBuilder;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final bool disableTapReveal;
  final double top;
  final double left;
  final double right;
  final double progress;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    var textStyle = TextStyle.lerp(
      TextStyles.display2,
      TextStyles.display3,
      progress,
    )!.copyWith(color: colors.textBase);
    if (MediaQuery.boldTextOf(context)) {
      textStyle = textStyle.merge(const TextStyle(fontWeight: FontWeight.bold));
    }

    final customTitleBuilder = titleBuilder;
    if (customTitleBuilder != null) {
      return Positioned(
        left: left,
        right: right,
        top: top,
        child: customTitleBuilder(
          context,
          HeaderAppBarTitleState(
            title: title,
            textStyle: textStyle,
            height: height,
          ),
        ),
      );
    }

    final canShowTitleTooltip = !disableTapReveal && onTap == null;

    return Positioned(
      left: left,
      right: right,
      top: top,
      child: canShowTitleTooltip
          ? LayoutBuilder(
              builder: (context, constraints) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: TooltipComponent(
                    message: title,
                    showDuration: _titleTooltipShowDuration,
                    onDoubleTap: onDoubleTap,
                    onLongPress: onLongPress,
                    child: SizedBox(
                      width: _singleLineTextWidth(
                        context,
                        title: title,
                        style: textStyle,
                        maxWidth: constraints.maxWidth,
                      ),
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textStyle,
                      ),
                    ),
                  ),
                );
              },
            )
          : onTap == null && onDoubleTap == null && onLongPress == null
          ? IgnorePointer(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
            )
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              onDoubleTap: onDoubleTap,
              onLongPress: onLongPress,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyle,
              ),
            ),
    );
  }
}

double _singleLineTextWidth(
  BuildContext context, {
  required String title,
  required TextStyle style,
  required double maxWidth,
}) {
  final textPainter = TextPainter(
    text: TextSpan(text: title, style: style),
    maxLines: 1,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout(maxWidth: maxWidth);
  return math.min(textPainter.width, maxWidth);
}
