import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:photos/ui/rewind/shell/rewind_page_scope.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_buttons.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/utils/share_util.dart";

class FinaleActions extends StatefulWidget {
  const FinaleActions({required this.active, required this.delayMs, super.key});

  final bool active;
  final int delayMs;

  @override
  State<FinaleActions> createState() => _FinaleActionsState();
}

class _FinaleActionsState extends State<FinaleActions> {
  final _shareButton = GlobalKey();

  void _share() {
    HapticFeedback.mediumImpact().ignore();
    RewindPageScope.navigatorOf(
      context,
    )?.shareVideo(shareButtonRect(context, _shareButton));
  }

  void _save() {
    HapticFeedback.selectionClick().ignore();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RewindEntrance(
          preset: RewindPreset.pop,
          active: widget.active,
          delayMs: widget.delayMs,
          child: RewindIdleLoop(
            idle: RewindIdle.pulse,
            active: widget.active,
            delayMs: widget.delayMs + 1600,
            child: _ShareButton(key: _shareButton, onTap: _share),
          ),
        ),
        const SizedBox(height: 12),
        RewindEntrance(
          preset: RewindPreset.line,
          active: widget.active,
          delayMs: widget.delayMs + 220,
          child: _SaveButton(onTap: _save),
        ),
      ],
    );
  }
}

class _ShareButton extends StatefulWidget {
  const _ShareButton({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  State<_ShareButton> createState() => _ShareButtonState();
}

class _ShareButtonState extends State<_ShareButton> {
  static const _width = 318.0;
  static const _height = 64.0;
  static const _lift = 6.0;
  static const _radius = BorderRadius.all(Radius.circular(_height / 2));

  var _pressed = false;

  void _press(bool pressed) {
    if (pressed != _pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: "Share your Rewind",
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        onTap: widget.onTap,
        child: SizedBox(
          width: _width,
          height: _height + _lift,
          child: Stack(
            children: [
              const Positioned(
                left: 0,
                right: 0,
                top: _lift,
                height: _height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: RewindColors.outline,
                    borderRadius: _radius,
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 90),
                curve: Curves.easeOut,
                left: 0,
                right: 0,
                top: _pressed ? _lift - 1 : 0,
                height: _height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: _radius,
                    border: Border.all(color: RewindColors.outline, width: 3),
                    gradient: const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, 0.6, 0.61, 1],
                      colors: [
                        Color(0xFFFF4FA6),
                        Color(0xFFF0308F),
                        Color(0xFFCB1F76),
                        Color(0xFFB8196A),
                      ],
                    ),
                  ),
                  child: Stack(
                    children: [
                      const Positioned(
                        right: 46,
                        top: 7,
                        width: 34,
                        height: 9,
                        child: _Shine(),
                      ),
                      const Positioned(
                        right: 88,
                        top: 8,
                        width: 12,
                        height: 7,
                        child: _Shine(),
                      ),
                      Center(
                        child: ExcludeSemantics(
                          child: Text(
                            "Share your Rewind",
                            style:
                                RewindTextStyles.numeral(
                                  27,
                                  color: RewindColors.cream,
                                ).copyWith(
                                  shadows: const [
                                    Shadow(
                                      color: Color(0x55800040),
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Shine extends StatelessWidget {
  const _Shine();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        color: Color(0x8CFFFFFF),
        borderRadius: BorderRadius.all(Radius.circular(9)),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: "Save to Ente",
      child: RewindPressable(
        onTap: onTap,
        child: Container(
          width: 300,
          height: 44,
          decoration: BoxDecoration(
            color: RewindColors.photoPaper,
            border: Border.all(
              color: RewindColors.ink.withValues(alpha: 0.85),
              width: 2.5,
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CustomPaint(
                  size: Size(18, 18),
                  painter: _DownloadPainter(),
                ),
                const SizedBox(width: 10),
                Text(
                  "Save to Ente",
                  style: RewindTextStyles.body(
                    17,
                    color: RewindColors.ink,
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DownloadPainter extends CustomPainter {
  const _DownloadPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final paint = Paint()
      ..color = RewindColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawLine(Offset(w / 2, 1), Offset(w / 2, h * 0.66), paint);
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.24, h * 0.42)
        ..lineTo(w / 2, h * 0.68)
        ..lineTo(w * 0.76, h * 0.42),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(1, h * 0.7)
        ..lineTo(1, h - 1)
        ..lineTo(w - 1, h - 1)
        ..lineTo(w - 1, h * 0.7),
      paint,
    );
  }

  @override
  bool shouldRepaint(_DownloadPainter oldDelegate) => false;
}
