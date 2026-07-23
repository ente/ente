import 'dart:async';
import 'dart:math' as math;

import 'package:ente_components/theme/radii.dart';
import 'package:ente_components/theme/spacing.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';

/// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=11025-18810&m=dev
/// Section: Tooltip
/// Specs: fill/light rounded tooltip bubble with a top pointer.
class TooltipBubbleComponent extends StatelessWidget {
  const TooltipBubbleComponent({
    super.key,
    required this.message,
    this.maxWidth = 320,
    this.backgroundColor,
    this.textColor,
    this.textStyle,
  });

  final String message;
  final double maxWidth;
  final Color? backgroundColor;
  final Color? textColor;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final effectiveTextStyle = (textStyle ?? TextStyles.mini).copyWith(
      color: textColor ?? colors.textBase,
      decoration: TextDecoration.none,
      decorationColor: Colors.transparent,
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: CustomPaint(
        painter: _TooltipBubblePainter(
          color: backgroundColor ?? colors.fillLight,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Spacing.lg,
            _tooltipVerticalPadding + _pointerDepth,
            Spacing.lg,
            _tooltipVerticalPadding,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Text(
              _breakableMessage(message),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
              textAlign: TextAlign.center,
              style: effectiveTextStyle,
            ),
          ),
        ),
      ),
    );
  }
}

class TooltipComponent extends StatefulWidget {
  const TooltipComponent({
    super.key,
    required this.message,
    required this.child,
    this.showDuration = const Duration(seconds: 3),
    this.maxWidth = 320,
    this.textStyle,
    this.onDoubleTap,
    this.onLongPress,
  });

  final String message;
  final Widget child;
  final Duration showDuration;
  final double maxWidth;
  final TextStyle? textStyle;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;

  @override
  State<TooltipComponent> createState() => _TooltipComponentState();
}

class _TooltipComponentState extends State<TooltipComponent> {
  OverlayEntry? _overlayEntry;
  Timer? _hideTimer;

  @override
  void dispose() {
    _hideTooltip();
    super.dispose();
  }

  void _showTooltip() {
    _hideTooltip();

    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox?;
    final targetBox = context.findRenderObject() as RenderBox?;
    if (overlayBox == null || targetBox == null || !targetBox.hasSize) {
      return;
    }

    final targetOffset = targetBox.localToGlobal(
      Offset.zero,
      ancestor: overlayBox,
    );
    final targetRect = targetOffset & targetBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return _TooltipOverlay(
          targetRect: targetRect,
          maxWidth: widget.maxWidth,
          message: widget.message,
          textStyle: widget.textStyle,
          onDismiss: _hideTooltip,
        );
      },
    );
    overlay.insert(_overlayEntry!);
    _hideTimer = Timer(widget.showDuration, _hideTooltip);
  }

  void _hideTooltip() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _showTooltip,
      onDoubleTap: widget.onDoubleTap,
      onLongPress: widget.onLongPress,
      child: widget.child,
    );
  }
}

class _TooltipOverlay extends StatelessWidget {
  const _TooltipOverlay({
    required this.targetRect,
    required this.maxWidth,
    required this.message,
    required this.textStyle,
    required this.onDismiss,
  });

  final Rect targetRect;
  final double maxWidth;
  final String message;
  final TextStyle? textStyle;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final textStyle = this.textStyle ?? TextStyles.mini;
    final maxBubbleWidth = math.min(
      maxWidth,
      screenWidth - (_screenPadding * 2),
    );
    final maxTextWidth = math.max(0.0, maxBubbleWidth - (Spacing.lg * 2));
    final textPainter = TextPainter(
      text: TextSpan(text: _breakableMessage(message), style: textStyle),
      maxLines: 3,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout(maxWidth: maxTextWidth);
    final bubbleWidth = math.min(
      maxBubbleWidth,
      textPainter.width + (Spacing.lg * 2),
    );
    final left = (targetRect.center.dx - (bubbleWidth / 2)).clamp(
      _screenPadding,
      math.max(_screenPadding, screenWidth - bubbleWidth - _screenPadding),
    );

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onDismiss,
        child: Stack(
          children: [
            Positioned(
              left: left.toDouble(),
              top: targetRect.bottom + _targetGap,
              width: bubbleWidth,
              child: TooltipBubbleComponent(
                message: message,
                maxWidth: bubbleWidth,
                textStyle: this.textStyle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TooltipBubblePainter extends CustomPainter {
  const _TooltipBubblePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final bodyRect = Rect.fromLTWH(
      0,
      _pointerDepth,
      size.width,
      size.height - _pointerDepth,
    );
    final pointerCenter = size.width / 2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(bodyRect, const Radius.circular(Radii.md)),
      )
      ..moveTo(pointerCenter - _pointerHalfWidth, bodyRect.top)
      ..lineTo(pointerCenter, bodyRect.top - _pointerDepth)
      ..lineTo(pointerCenter + _pointerHalfWidth, bodyRect.top)
      ..close();

    canvas.drawShadow(path, const Color(0x33000000), 18, true);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TooltipBubblePainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

String _breakableMessage(String message) {
  return message.replaceAllMapped(
    RegExp(r'([@._-])'),
    (match) => '${match.group(0)}\u200B',
  );
}

const _tooltipVerticalPadding = 10.0;
const _pointerDepth = 7.0;
const _pointerHalfWidth = 6.0;
const _targetGap = 4.0;
const _screenPadding = 8.0;
