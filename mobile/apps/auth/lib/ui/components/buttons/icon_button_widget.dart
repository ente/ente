import 'package:ente_auth/theme/colors.dart';
import 'package:ente_auth/theme/ente_theme.dart';
import 'package:flutter/material.dart';

enum IconButtonType { primary, secondary, rounded }

class IconButtonWidget extends StatefulWidget {
  final IconButtonType iconButtonType;
  final IconData icon;
  final bool disableGestureDetector;
  final VoidCallback? onTap;
  final Color? defaultColor;
  final Color? pressedColor;
  final Color? iconColor;
  final EdgeInsetsGeometry padding;
  final double size;

  const IconButtonWidget({
    super.key,
    required this.icon,
    required this.iconButtonType,
    this.disableGestureDetector = false,
    this.onTap,
    this.defaultColor,
    this.pressedColor,
    this.iconColor,
    this.padding = const EdgeInsets.all(8),
    this.size = 24,
  });

  @override
  State<IconButtonWidget> createState() => _IconButtonWidgetState();
}

class _IconButtonWidgetState extends State<IconButtonWidget> {
  Color? iconStateColor;
  @override
  void didChangeDependencies() {
    setState(() {
      iconStateColor = null;
    });
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasPressedState = widget.onTap != null;
    final colorTheme = getEnteColorScheme(context);
    iconStateColor ??
        (iconStateColor =
            widget.defaultColor ??
            (widget.iconButtonType == IconButtonType.rounded
                ? colorTheme.fillFaint
                : null));
    return widget.disableGestureDetector
        ? _iconButton(colorTheme)
        : GestureDetector(
            onTapDown: hasPressedState ? _onTapDown : null,
            onTapUp: hasPressedState ? _onTapUp : null,
            onTapCancel: hasPressedState ? _onTapCancel : null,
            onTap: widget.onTap,
            child: _iconButton(colorTheme),
          );
  }

  Widget _iconButton(EnteColorScheme colorTheme) {
    return Padding(
      padding: const EdgeInsets.all(4.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 20),
        padding: widget.padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(
            widget.iconButtonType == IconButtonType.rounded ? widget.size : 20,
          ),
          color: iconStateColor,
        ),
        child: Icon(
          widget.icon,
          color:
              widget.iconColor ??
              (widget.iconButtonType == IconButtonType.secondary
                  ? colorTheme.strokeMuted
                  : colorTheme.strokeBase),
          size: widget.size,
        ),
      ),
    );
  }

  void _onTapDown(TapDownDetails details) {
    final colorTheme = getEnteColorScheme(context);
    setState(() {
      iconStateColor =
          widget.pressedColor ??
          (widget.iconButtonType == IconButtonType.rounded
              ? colorTheme.fillMuted
              : colorTheme.fillFaint);
    });
  }

  void _onTapUp(TapUpDetails details) {
    Future.delayed(const Duration(milliseconds: 100), () {
      setState(() {
        iconStateColor = null;
      });
    });
  }

  void _onTapCancel() {
    setState(() {
      iconStateColor = null;
    });
  }
}
