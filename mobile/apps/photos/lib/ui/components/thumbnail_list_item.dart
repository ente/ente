import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";

Color thumbnailListItemBackgroundColor(BuildContext context) {
  return context.componentColors.fillLight;
}

class ThumbnailListItem extends StatefulWidget {
  static const defaultPadding = EdgeInsets.all(8);
  static const defaultLeadingSize = 52.0;
  static const defaultLeadingRadius = 12.0;
  static const defaultBorderRadius = 20.0;
  static const defaultContentSpacing = 12.0;
  static const defaultItemSpacing = 8.0;
  static const _stateTransitionDuration = Duration(milliseconds: 120);

  final Widget leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;
  final EdgeInsetsGeometry padding;
  final double leadingSize;
  final double borderRadius;
  final double contentSpacing;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? selectedBorderColor;

  const ThumbnailListItem({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.isSelected = false,
    this.padding = defaultPadding,
    this.leadingSize = defaultLeadingSize,
    this.borderRadius = defaultBorderRadius,
    this.contentSpacing = defaultContentSpacing,
    this.backgroundColor,
    this.borderColor,
    this.selectedBorderColor,
  });

  @override
  State<ThumbnailListItem> createState() => _ThumbnailListItemState();
}

class _ThumbnailListItemState extends State<ThumbnailListItem> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final child = AnimatedContainer(
      duration: ThumbnailListItem._stateTransitionDuration,
      width: double.infinity,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: _backgroundColor(colors),
        borderRadius: BorderRadius.all(Radius.circular(widget.borderRadius)),
        border: Border.all(
          color: widget.isSelected
              ? widget.selectedBorderColor ?? colors.strokeDark
              : widget.borderColor ?? _backgroundColor(colors),
        ),
      ),
      child: Row(
        children: [
          SizedBox.square(dimension: widget.leadingSize, child: widget.leading),
          SizedBox(width: widget.contentSpacing),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                widget.title,
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 2),
                  widget.subtitle!,
                ],
              ],
            ),
          ),
          if (widget.trailing != null) ...[
            SizedBox(width: widget.contentSpacing),
            widget.trailing!,
          ],
        ],
      ),
    );

    if (widget.onTap == null && widget.onLongPress == null) {
      return child;
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onHighlightChanged: _setPressed,
        borderRadius: BorderRadius.circular(widget.borderRadius),
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        child: child,
      ),
    );
  }

  Color _backgroundColor(ColorTokens colors) {
    if (_isPressed) {
      return colors.fillDarker;
    }
    return widget.backgroundColor ?? colors.fillLight;
  }

  void _setPressed(bool value) {
    if (_isPressed == value) {
      return;
    }
    setState(() {
      _isPressed = value;
    });
  }
}
