import 'dart:io';
import 'dart:math' as math;

import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:locker/services/scanner/scanner_models.dart';
import 'package:locker/ui/pages/scanner/capture_flight.dart';
import 'package:locker/ui/pages/scanner/delayed_reveal.dart';
import 'package:locker/ui/pages/scanner/scanner_review_page.dart';

class ScannerProcessedThumbnail extends StatelessWidget {
  const ScannerProcessedThumbnail({super.key, required this.page});

  static const _inset = CaptureFlightTuning.thumbnailInset;
  static const _zoom = 1 / (1 - 2 * _inset);

  final ScannedPage page;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final box = constraints.biggest;
        final aspect = page.height == 0 ? 1.0 : page.width / page.height;
        final size = aspect < 1
            ? Size(box.width * _zoom, box.width * _zoom / aspect)
            : Size(box.height * _zoom * aspect, box.height * _zoom);
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: Transform.translate(
              offset: Offset(0, -size.height * _inset),
              child: SizedBox.fromSize(
                size: size,
                child: Image(
                  image: ResizeImage(
                    FileImage(page.processedJpeg),
                    height:
                        (size.height * MediaQuery.devicePixelRatioOf(context))
                            .round(),
                  ),
                  fit: BoxFit.fill,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class ScannerCameraMessage extends StatelessWidget {
  const ScannerCameraMessage({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyles.body.copyWith(color: colors.specialWhite),
            ),
            const SizedBox(height: Spacing.xl),
            ButtonComponent(
              label: context.strings.retry,
              size: ButtonComponentSize.small,
              onTap: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

class ScannerPreparingHint extends StatelessWidget {
  const ScannerPreparingHint({super.key, required this.visible});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return DelayedReveal(
      visible: visible,
      delay: const Duration(seconds: 5),
      child: Padding(
        padding: const EdgeInsets.only(bottom: Spacing.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md,
            vertical: Spacing.sm,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.specialWhite,
                ),
              ),
              const SizedBox(width: Spacing.sm),
              Text(
                context.strings.scannerPreparing,
                style: TextStyles.mini.copyWith(color: colors.specialWhite),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ScannerChromeButton extends StatelessWidget {
  const ScannerChromeButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final List<List<dynamic>> icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final button = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.4),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: HugeIcon(
            icon: icon,
            color: onTap == null
                ? colors.specialWhite.withValues(alpha: 0.4)
                : colors.specialWhite,
            size: 22,
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

class ScannerShutterButton extends StatefulWidget {
  const ScannerShutterButton({
    super.key,
    required this.enabled,
    required this.onTap,
  });

  final bool enabled;
  final Future<void> Function() onTap;

  @override
  State<ScannerShutterButton> createState() => _ScannerShutterButtonState();
}

class _ScannerShutterButtonState extends State<ScannerShutterButton> {
  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final white = colors.specialWhite;
    return Tooltip(
      message: context.strings.scannerCapture,
      child: GestureDetector(
        onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.enabled ? () => widget.onTap() : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: widget.enabled ? 1 : 0.5,
          child: AnimatedScale(
            scale: _pressed ? 0.9 : 1,
            duration: _pressed ? Motion.quick : Motion.slow,
            curve: _pressed ? Curves.easeOut : Curves.easeOutBack,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: white, width: 4),
              ),
              child: Center(
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ScannerModeToggle extends StatelessWidget {
  const ScannerModeToggle({
    super.key,
    required this.active,
    required this.onTap,
  });

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final labelStyle = TextStyles.mini.copyWith(color: colors.specialWhite);
    return Tooltip(
      message: active
          ? context.strings.scannerAutoCaptureOff
          : context.strings.scannerAutoCaptureOn,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedCameraAutomatically01,
                color: colors.specialWhite,
                size: 20,
              ),
              const SizedBox(width: Spacing.xs),
              Stack(
                alignment: Alignment.center,
                children: [
                  for (final label in [
                    context.strings.scannerCaptureModeAuto,
                    context.strings.scannerCaptureModeManual,
                  ])
                    Opacity(opacity: 0, child: Text(label, style: labelStyle)),
                  Text(
                    active
                        ? context.strings.scannerCaptureModeAuto
                        : context.strings.scannerCaptureModeManual,
                    style: labelStyle,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ScannerActionReveal extends StatelessWidget {
  const ScannerActionReveal({
    super.key,
    required this.visible,
    required this.revealDuration,
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  static const size = 62.0;

  final bool visible;
  final Duration revealDuration;
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedScale(
        scale: visible ? 1 : 0,
        duration: revealDuration,
        curve: visible ? Curves.easeOutBack : Curves.easeIn,
        child: Tooltip(
          message: tooltip,
          child: GestureDetector(
            onTap: onTap,
            child: SizedBox(width: size, height: size, child: child),
          ),
        ),
      ),
    );
  }
}

class ScannerPagesButton extends StatefulWidget {
  const ScannerPagesButton({
    super.key,
    required this.count,
    required this.thumbnail,
    required this.heroFile,
    required this.accent,
    required this.onTap,
  });

  static const borderWidth = 2.0;
  static const maxStackedSheets = 2;

  final int count;
  final Widget? thumbnail;
  final File? heroFile;
  final Color accent;
  final VoidCallback onTap;

  @override
  State<ScannerPagesButton> createState() => _ScannerPagesButtonState();
}

class _ScannerPagesButtonState extends State<ScannerPagesButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(
        begin: 1.0,
        end: 1.12,
      ).chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(
        begin: 1.12,
        end: 1.0,
      ).chain(CurveTween(curve: Curves.easeInOut)),
      weight: 60,
    ),
  ]).animate(_bounce);

  Duration _switchDuration = Duration.zero;

  @override
  void didUpdateWidget(ScannerPagesButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count > oldWidget.count) _bounce.forward(from: 0);
    if (widget.thumbnail?.key != oldWidget.thumbnail?.key) {
      _switchDuration = widget.thumbnail is CaptureSnapshotThumbnail
          ? Duration.zero
          : Motion.standard;
    }
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  static Widget _expandedLayout(Widget? current, List<Widget> previous) =>
      Stack(fit: StackFit.expand, children: [...previous, ?current]);

  Widget _stackedSheet(int depth, ColorTokens colors) {
    final visible = widget.count > depth;
    final angle = (depth.isOdd ? -5.0 : 4.0) * math.pi / 180;
    final shift = Offset(depth.isOdd ? -1 : 2, -2.0 * depth);
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: Motion.standard,
          opacity: visible ? 1 : 0,
          child: AnimatedScale(
            duration: Motion.standard,
            curve: Curves.easeOutBack,
            scale: visible ? 1 : 0.8,
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.translationValues(shift.dx, shift.dy, 0)
                ..rotateZ(angle),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.md),
                  color: colors.specialWhite.withValues(
                    alpha: depth == 1 ? 0.85 : 0.6,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return ScannerActionReveal(
      visible: widget.count > 0,
      revealDuration: Duration.zero,
      tooltip: context.strings.review,
      onTap: widget.onTap,
      child: ScaleTransition(
        scale: _scale,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (
              var depth = ScannerPagesButton.maxStackedSheets;
              depth >= 1;
              depth--
            )
              _stackedSheet(depth, colors),
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.md),
                  color: Colors.black.withValues(alpha: 0.4),
                  border: Border.all(
                    color: colors.specialWhite,
                    width: ScannerPagesButton.borderWidth,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: ScannerPageHero(
                  file: widget.heroFile,
                  primary: false,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      Radii.md - ScannerPagesButton.borderWidth,
                    ),
                    child: AnimatedSwitcher(
                      duration: _switchDuration,
                      layoutBuilder: _expandedLayout,
                      child:
                          widget.thumbnail ??
                          const SizedBox.expand(key: ValueKey('empty')),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.count > 0)
              Positioned(
                top: -Spacing.sm,
                right: -Spacing.sm,
                child: Container(
                  padding: const EdgeInsets.all(Spacing.xs),
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.accent,
                    border: Border.all(
                      color: colors.specialWhite,
                      width: ScannerPagesButton.borderWidth,
                    ),
                  ),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: Motion.standard,
                      transitionBuilder: (child, animation) =>
                          ScaleTransition(scale: animation, child: child),
                      child: Text(
                        '${widget.count}',
                        key: ValueKey(widget.count),
                        style: TextStyles.mini.copyWith(
                          color: colors.specialWhite,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ScannerDoneButton extends StatelessWidget {
  const ScannerDoneButton({
    super.key,
    required this.visible,
    required this.accent,
    required this.onTap,
  });

  final bool visible;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return ScannerActionReveal(
      visible: visible,
      revealDuration: Motion.standard,
      tooltip: context.strings.done,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: accent,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 10,
            ),
          ],
        ),
        child: Center(
          child: HugeIcon(
            icon: HugeIcons.strokeRoundedTick02,
            color: colors.specialWhite,
            size: 30,
          ),
        ),
      ),
    );
  }
}
