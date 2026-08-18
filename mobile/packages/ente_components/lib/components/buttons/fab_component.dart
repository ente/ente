import "dart:async";

import "package:ente_components/theme/motion.dart";
import "package:ente_components/theme/text_styles.dart";
import "package:ente_components/theme/theme.dart";
import "package:flutter/material.dart";

enum FABComponentVariant { primary, secondary }

/// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=21843-6537&m=dev
class FABComponent extends StatefulWidget {
  final String? label;

  final FutureOr<void> Function()? onTap;

  final FABComponentVariant variant;

  final bool isDisabled;

  final Widget? icon;

  const FABComponent({
    super.key,
    this.icon,
    this.label,
    this.onTap,
    this.variant = FABComponentVariant.primary,
    this.isDisabled = false,
  }) : assert(
         icon != null || label != null,
         "Either icon or label is required",
       );

  @override
  State<FABComponent> createState() => _FABComponentState();
}

class _FABComponentState extends State<FABComponent> {
  bool _isExecuting = false;
  bool _isPressed = false;

  @override
  void didUpdateWidget(covariant FABComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isDisabled && !oldWidget.isDisabled) {
      _isPressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled =
        !widget.isDisabled && widget.onTap != null && !_isExecuting;
    final colors = context.componentColors;
    final backgroundColor = switch (widget.variant) {
      FABComponentVariant.primary =>
        _isPressed ? colors.primaryDark : colors.primary,
      FABComponentVariant.secondary =>
        _isPressed ? colors.fillDarker : colors.fillDark,
    };
    final foregroundColor = switch (widget.variant) {
      FABComponentVariant.primary => colors.specialWhite,
      FABComponentVariant.secondary => colors.primary,
    };
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: isEnabled ? _handleTap : null,
      onTapDown: isEnabled ? (_) => _setPressed(true) : null,
      onTapUp: isEnabled ? (_) => _setPressed(false) : null,
      onTapCancel: isEnabled ? () => _setPressed(false) : null,
      child: AnimatedScale(
        scale: _isPressed ? 0.98 : 1,
        duration: Motion.quick,
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: Motion.standard,
          curve: Curves.easeInOutCubic,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(9999),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 52, minHeight: 52),
            child: Padding(
              padding: switch ((widget.icon, widget.label)) {
                (_, null) => EdgeInsets.zero,
                (null, _) => const EdgeInsets.symmetric(horizontal: 24),
                (_, _) => const EdgeInsets.only(left: 20, right: 24),
              },
              child: Row(
                spacing: 8,
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null)
                    IconTheme.merge(
                      data: IconThemeData(color: foregroundColor),
                      child: widget.icon!,
                    ),
                  if (widget.label != null)
                    Text(
                      widget.label!,
                      style: TextStyles.bodyBold.copyWith(
                        color: foregroundColor,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setPressed(bool value) {
    if (_isPressed == value) return;
    setState(() => _isPressed = value);
  }

  Future<void> _handleTap() async {
    final callback = widget.onTap;
    if (callback == null || _isExecuting) return;

    setState(() {
      _isExecuting = true;
      _isPressed = false;
    });

    try {
      await Future.sync(callback);
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isExecuting = false);
      }
    }
  }
}
