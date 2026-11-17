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
        const SizedBox(height: 16),
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
  static const _width = 232.0;
  static const _height = 62.0;
  static const _lift = 5.0;
  static const _fill = RewindColors.yellow;
  static const _label = RewindColors.ink;

  var _pressed = false;

  void _press(bool pressed) {
    if (pressed != _pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final sink = _pressed ? _lift - 1 : 0.0;
    return Semantics(
      button: true,
      label: "Share",
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
              Positioned(
                left: 0,
                right: 0,
                top: _lift,
                height: _height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: RewindColors.outline,
                    borderRadius: BorderRadius.circular(_height / 2),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 90),
                curve: Curves.easeOut,
                left: 0,
                right: 0,
                top: sink,
                height: _height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _fill,
                    border: Border.all(color: RewindColors.outline, width: 3),
                    borderRadius: BorderRadius.circular(_height / 2),
                  ),
                  child: ExcludeSemantics(
                    child: Center(
                      child: Text(
                        "Share",
                        style: RewindTextStyles.body(
                          25,
                          color: _label,
                          height: 1.05,
                        ),
                      ),
                    ),
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
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            border: Border.all(
              color: RewindColors.cream.withValues(alpha: 0.85),
              width: 2,
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          child: ExcludeSemantics(
            child: Center(
              widthFactor: 1,
              child: Text(
                "Save to Ente",
                style: RewindTextStyles.body(17, height: 1.05),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
