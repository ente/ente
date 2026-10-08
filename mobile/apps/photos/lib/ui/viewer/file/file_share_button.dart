import "dart:async";
import "dart:io";
import "dart:math" as math;

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/cupertino.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";

enum _FileShareAction { file, link }

class FileShareButton extends StatefulWidget {
  const FileShareButton({
    required this.canSendLink,
    required this.isVideo,
    required this.onSendFile,
    required this.onSendLink,
    super.key,
  });

  final bool canSendLink;
  final bool isVideo;
  final FutureOr<void> Function() onSendFile;
  final FutureOr<void> Function() onSendLink;

  @override
  State<FileShareButton> createState() => _FileShareButtonState();
}

class _FileShareButtonState extends State<FileShareButton> {
  _FileShareRoute? _route;

  @override
  void dispose() {
    final route = _route;
    if (route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: context.strings.share,
      icon: Platform.isAndroid
          ? const HugeIcon(
              icon: HugeIcons.strokeRoundedShare08,
              color: Colors.white,
            )
          : const Icon(CupertinoIcons.share, color: Colors.white),
      onPressed: _share,
    );
  }

  Future<void> _share() async {
    if (_route != null) return;
    final sendFile = widget.onSendFile;
    final sendLink = widget.onSendLink;
    if (!widget.canSendLink) {
      await sendFile();
      return;
    }

    final navigator = Navigator.of(context);
    Rect anchorRect() {
      final button = context.findRenderObject()! as RenderBox;
      final overlay =
          navigator.overlay!.context.findRenderObject()! as RenderBox;
      return button.localToGlobal(Offset.zero, ancestor: overlay) & button.size;
    }

    final initialAnchor = anchorRect();
    final route = _FileShareRoute(
      anchorRect: () => mounted ? anchorRect() : initialAnchor,
      fileLabel: widget.isVideo
          ? context.strings.sendVideo
          : context.strings.sendPhoto,
      linkLabel: context.strings.sendLink,
      shareLabel: context.strings.share,
      closeLabel: context.strings.close,
      isVideo: widget.isVideo,
      reduceMotion: MediaQuery.disableAnimationsOf(context),
      themes: InheritedTheme.capture(from: context, to: navigator.context),
    );
    _route = route;
    final action = await navigator.push(route);
    // Native sharing must wait until the popup's overlay has been removed.
    await route.completed;
    _route = null;
    if (!mounted) return;
    switch (action) {
      case _FileShareAction.file:
        await sendFile();
      case _FileShareAction.link:
        await sendLink();
      case null:
        break;
    }
  }
}

class _FileShareRoute extends PopupRoute<_FileShareAction> {
  _FileShareRoute({
    required this.anchorRect,
    required this.fileLabel,
    required this.linkLabel,
    required this.shareLabel,
    required this.closeLabel,
    required this.isVideo,
    required this.reduceMotion,
    required this.themes,
  });

  final Rect Function() anchorRect;
  final String fileLabel;
  final String linkLabel;
  final String shareLabel;
  final String closeLabel;
  final bool isVideo;
  final bool reduceMotion;
  final CapturedThemes themes;

  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => true;
  @override
  String get barrierLabel => closeLabel;
  @override
  Duration get transitionDuration =>
      Duration(milliseconds: reduceMotion ? 120 : 260);
  @override
  Duration get reverseTransitionDuration =>
      Duration(milliseconds: reduceMotion ? 120 : 140);

  void _select([_FileShareAction? action]) {
    if (isCurrent) navigator!.pop(action);
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return themes.wrap(
      LayoutBuilder(
        builder: (context, constraints) {
          final mediaQuery = MediaQuery.of(context);
          final anchor = anchorRect();
          return Semantics(
            scopesRoute: true,
            namesRoute: true,
            label: shareLabel,
            explicitChildNodes: true,
            child: Stack(
              children: [
                CustomSingleChildLayout(
                  delegate: _ShareDockLayout(anchor, mediaQuery.padding),
                  child: _ShareDockTransition(
                    animation: animation,
                    reduceMotion: reduceMotion,
                    child: _ShareDock(
                      fileLabel: fileLabel,
                      linkLabel: linkLabel,
                      isVideo: isVideo,
                      maxHalfWidth:
                          (constraints.maxWidth -
                              mediaQuery.padding.horizontal) *
                          0.35,
                      onSelected: _select,
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: anchor,
                  child: Semantics(
                    button: true,
                    label: closeLabel,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _select,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ShareDockTransition extends StatelessWidget {
  const _ShareDockTransition({
    required this.animation,
    required this.reduceMotion,
    required this.child,
  });

  final Animation<double> animation;
  final bool reduceMotion;
  final Widget child;

  static const _riseCurve = Cubic(0.2, 0.7, 0.3, 1);
  static final _scale = Tween<double>(
    begin: 0.96,
    end: 1,
  ).chain(CurveTween(curve: _riseCurve));
  static final _offset = Tween<double>(
    begin: 14,
    end: 0,
  ).chain(CurveTween(curve: _riseCurve));

  @override
  Widget build(BuildContext context) {
    if (reduceMotion) {
      return FadeTransition(opacity: animation, child: child);
    }
    return DualTransitionBuilder(
      animation: animation,
      forwardBuilder: (context, entrance, child) => FadeTransition(
        opacity: entrance.drive(
          CurveTween(curve: const Interval(0, 0.68, curve: _riseCurve)),
        ),
        child: AnimatedBuilder(
          animation: entrance,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, _offset.transform(entrance.value)),
            child: Transform.scale(
              scale: _scale.transform(entrance.value),
              alignment: Alignment.bottomCenter,
              child: child,
            ),
          ),
          child: child,
        ),
      ),
      reverseBuilder: (context, exit, child) {
        final closing = exit.drive(CurveTween(curve: Curves.easeIn));
        return FadeTransition(
          opacity: ReverseAnimation(closing),
          child: AnimatedBuilder(
            animation: closing,
            builder: (context, child) => Transform.translate(
              offset: Offset(0, 6 * closing.value),
              child: Transform.scale(
                scale: 1 - 0.02 * closing.value,
                alignment: Alignment.bottomCenter,
                child: child,
              ),
            ),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class _ShareDockLayout extends SingleChildLayoutDelegate {
  const _ShareDockLayout(this.anchor, this.padding);

  final Rect anchor;
  final EdgeInsets padding;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: math.max(0, constraints.maxWidth - padding.horizontal - 32),
      maxHeight: math.max(0, anchor.top - padding.top - 24),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    return Offset(
      (anchor.center.dx - childSize.width / 2).clamp(
        padding.left + 16,
        size.width - padding.right - childSize.width - 16,
      ),
      anchor.top - childSize.height - 12,
    );
  }

  @override
  bool shouldRelayout(_ShareDockLayout oldDelegate) =>
      anchor != oldDelegate.anchor || padding != oldDelegate.padding;
}

class _ShareDock extends StatelessWidget {
  const _ShareDock({
    required this.fileLabel,
    required this.linkLabel,
    required this.isVideo,
    required this.maxHalfWidth,
    required this.onSelected,
  });

  final String fileLabel;
  final String linkLabel;
  final bool isVideo;
  final double maxHalfWidth;
  final ValueChanged<_FileShareAction> onSelected;

  static final _labelStyle = TextStyles.body.copyWith(color: Colors.white);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        final painter = TextPainter(
          textDirection: Directionality.of(context),
          textScaler: textScaler,
        );
        var contentWidth = 26.0;
        for (final label in [fileLabel, linkLabel]) {
          painter.text = TextSpan(text: label, style: _labelStyle);
          painter.layout();
          contentWidth = math.max(contentWidth, painter.width);
        }
        final halfWidth = math.min(
          maxHalfWidth,
          math.max(kMinInteractiveDimension, contentWidth + 24),
        );
        final dockWidth = math.min(constraints.maxWidth, halfWidth * 2 + 17);
        var stacked = false;
        if (textScaler.scale(_labelStyle.fontSize!) >=
            _labelStyle.fontSize! * 2) {
          painter.maxLines = 2;
          for (final label in [fileLabel, linkLabel]) {
            painter.text = TextSpan(text: label, style: _labelStyle);
            painter.layout(maxWidth: math.max(0, (dockWidth - 17) / 2 - 24));
            stacked |= painter.didExceedMaxLines;
          }
        }
        painter.dispose();

        final file = _action(
          label: fileLabel,
          icon: isVideo
              ? HugeIcons.strokeRoundedVideo01
              : HugeIcons.strokeRoundedImage01,
          action: _FileShareAction.file,
          stacked: stacked,
        );
        final link = _action(
          label: linkLabel,
          icon: HugeIcons.strokeRoundedLink02,
          action: _FileShareAction.link,
          stacked: stacked,
        );
        final dividerColor = Colors.white.withValues(alpha: 0.16);
        return SizedBox(
          width: stacked ? math.min(360, constraints.maxWidth) : dockWidth,
          child: Material(
            key: const ValueKey("file-share-dock"),
            color: ColorTokens.dark.fillLight.withValues(alpha: 0.96),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
            ),
            clipBehavior: Clip.antiAlias,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(8),
              child: stacked
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        file,
                        Divider(height: 1, thickness: 1, color: dividerColor),
                        link,
                      ],
                    )
                  : IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: file),
                          VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: dividerColor,
                          ),
                          Expanded(child: link),
                        ],
                      ),
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _action({
    required String label,
    required List<List<dynamic>> icon,
    required _FileShareAction action,
    required bool stacked,
  }) {
    final iconWidget = HugeIcon(icon: icon, color: Colors.white, size: 26);
    final text = Text(
      label,
      style: _labelStyle,
      textAlign: stacked ? TextAlign.start : TextAlign.center,
    );
    return InkWell(
      key: ValueKey("file-share-${action.name}"),
      borderRadius: BorderRadius.circular(16),
      onTap: () => onSelected(action),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: stacked ? 64 : 88),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          child: stacked
              ? Row(
                  children: [
                    iconWidget,
                    const SizedBox(width: 16),
                    Expanded(child: text),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [iconWidget, const SizedBox(height: 10), text],
                ),
        ),
      ),
    );
  }
}
