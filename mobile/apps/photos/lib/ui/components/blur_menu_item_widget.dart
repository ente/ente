import 'package:flutter/material.dart';
import 'package:photos/theme/ente_theme.dart';

class BlurMenuItemWidget extends StatefulWidget {
  final IconData? leadingIcon;
  final String? labelText;
  final Color? menuItemColor;
  final Color? pressedColor;
  final VoidCallback? onTap;
  const BlurMenuItemWidget({
    this.leadingIcon,
    this.labelText,
    this.menuItemColor,
    this.pressedColor,
    this.onTap,
    super.key,
  });

  @override
  State<BlurMenuItemWidget> createState() => _BlurMenuItemWidgetState();
}

class _BlurMenuItemWidgetState extends State<BlurMenuItemWidget> {
  Color? menuItemColor;
  bool isDisabled = false;

  @override
  void initState() {
    menuItemColor = widget.menuItemColor;
    isDisabled = (widget.onTap == null);
    super.initState();
  }

  @override
  void didChangeDependencies() {
    menuItemColor = widget.menuItemColor;
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    isDisabled = (widget.onTap == null);
    final colorScheme = getEnteColorScheme(context);
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onCancel,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 20),
        color: isDisabled ? colorScheme.fillFaint : menuItemColor,
        padding: const EdgeInsets.only(left: 16, right: 12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              widget.leadingIcon != null
                  ? Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Icon(
                        widget.leadingIcon,
                        size: 20,
                        color: isDisabled
                            ? colorScheme.strokeMuted
                            : colorScheme.blurStrokeBase,
                      ),
                    )
                  : const SizedBox.shrink(),
              widget.labelText != null
                  ? Flexible(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                widget.labelText!,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: getEnteTextTheme(context).bodyBold
                                    .copyWith(
                                      color: isDisabled
                                          ? colorScheme.textFaint
                                          : colorScheme.blurTextBase,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );
  }

  void _onTapDown(TapDownDetails details) {
    setState(() {
      menuItemColor = widget.pressedColor ?? widget.menuItemColor;
    });
  }

  void _onTapUp(TapUpDetails details) {
    Future.delayed(
      const Duration(milliseconds: 100),
      () => setState(() {
        menuItemColor = widget.menuItemColor;
      }),
    );
  }

  void _onCancel() {
    setState(() {
      menuItemColor = widget.menuItemColor;
    });
  }
}
