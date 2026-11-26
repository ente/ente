import "dart:math";

import "package:ente_components/hugeicons.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:photos/core/configuration.dart";
import "package:photos/ui/rewind/copy/rewind_copy.dart";
import "package:photos/ui/rewind/shell/rewind_page_scope.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_svg.dart";
import "package:photos/utils/share_util.dart";

typedef _Artwork = ({
  String asset,
  Rect rect,
  double turnDeg,
  Rect face,
  Rect icon,
  double iconStroke,
  Offset textCenter,
  double textSize,
  Color color,
});

const _shareArtwork = (
  asset: RewindAssets.finaleShareButton,
  rect: Rect.fromLTWH(50, 411.87, 299.159, 138.81),
  turnDeg: -1.41,
  face: Rect.fromLTRB(9, 16, 290, 119),
  icon: Rect.fromLTWH(36.36, 52.26, 24.18, 24.18),
  iconStroke: 2.18,
  textCenter: Offset(165.84, 64.2),
  textSize: 22.539,
  color: RewindColors.cream,
);

const _saveArtwork = (
  asset: RewindAssets.finaleSaveButton,
  rect: Rect.fromLTWH(100.92, 526.85, 201.641, 93.561),
  turnDeg: -1.98,
  face: Rect.fromLTRB(6, 10, 196, 80),
  icon: Rect.fromLTWH(36.22, 33.51, 17.43, 17.43),
  iconStroke: 2.4,
  textCenter: Offset(106.82, 42.1),
  textSize: 15.689,
  color: RewindColors.outline,
);

class FinaleActions extends StatefulWidget {
  const FinaleActions({
    required this.active,
    required this.delayMs,
    required this.elapsedMs,
    super.key,
  });

  final bool active;
  final int delayMs;
  final ValueListenable<double> elapsedMs;

  @override
  State<FinaleActions> createState() => _FinaleActionsState();
}

class _FinaleActionsState extends State<FinaleActions> {
  static const _saveDelayMs = 220;

  final _shareButton = GlobalKey();

  void _share() {
    HapticFeedback.mediumImpact().ignore();
    RewindPageScope.navigatorOf(
      context,
    )?.shareVideo(shareButtonRect(context, _shareButton));
  }

  void _save() {
    HapticFeedback.selectionClick().ignore();
    RewindPageScope.navigatorOf(context)?.saveVideo();
  }

  @override
  Widget build(BuildContext context) {
    final copy = RewindCopy.of(context);
    final videoSaved = RewindPageScope.navigatorOf(context)?.videoSaved;
    final still = MediaQuery.disableAnimationsOf(context);
    final saveAtMs = widget.delayMs + _saveDelayMs;
    return Stack(
      children: [
        if (Configuration.instance.hasConfiguredAccount())
          _place(
            _saveArtwork,
            ValueListenableBuilder(
              valueListenable: widget.elapsedMs,
              builder: (context, ms, save) =>
                  IgnorePointer(ignoring: !still && ms < saveAtMs, child: save),
              child: RewindEntrance(
                preset: RewindPreset.line,
                active: widget.active,
                delayMs: saveAtMs,
                child: ValueListenableBuilder(
                  valueListenable:
                      videoSaved ?? const AlwaysStoppedAnimation(false),
                  builder: (context, saved, _) => _ArtworkButton(
                    artwork: _saveArtwork,
                    label: saved ? copy.savedVideo : copy.saveVideo,
                    icon: saved
                        ? HugeIcons.strokeRoundedTick02
                        : HugeIcons.strokeRoundedDownload04,
                    onTap: saved ? null : _save,
                  ),
                ),
              ),
            ),
          ),
        _place(
          _shareArtwork,
          RewindEntrance(
            preset: RewindPreset.pop,
            active: widget.active,
            delayMs: widget.delayMs,
            child: RewindIdleLoop(
              idle: RewindIdle.pulse,
              active: widget.active,
              delayMs: widget.delayMs + 1600,
              child: _ArtworkButton(
                key: _shareButton,
                artwork: _shareArtwork,
                label: copy.shareRewind,
                icon: HugeIcons.strokeRoundedVideo01,
                onTap: _share,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _place(_Artwork artwork, Widget child) {
    return Positioned.fromRect(
      rect: artwork.rect,
      child: Transform.rotate(angle: artwork.turnDeg * pi / 180, child: child),
    );
  }
}

class _ArtworkButton extends StatefulWidget {
  const _ArtworkButton({
    required this.artwork,
    required this.label,
    required this.icon,
    required this.onTap,
    super.key,
  });

  final _Artwork artwork;
  final String label;
  final List<List<dynamic>> icon;
  final VoidCallback? onTap;

  @override
  State<_ArtworkButton> createState() => _ArtworkButtonState();
}

class _ArtworkButtonState extends State<_ArtworkButton> {
  var _pressed = false;

  void _press(bool pressed) {
    if (pressed != _pressed) setState(() => _pressed = pressed);
  }

  Rect _labelRect(TextStyle style, TextScaler scaler) {
    final artwork = widget.artwork;
    final painter = TextPainter(
      text: TextSpan(text: widget.label, style: style),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final width = painter.width;
    painter.dispose();
    final margin = artwork.icon.left - artwork.face.left;
    final left = artwork.icon.right + artwork.icon.width * 0.4;
    final right = artwork.face.right - margin;
    final fitted = min(width, right - left);
    final start = max(
      left,
      min(artwork.textCenter.dx - fitted / 2, right - fitted),
    );
    return Rect.fromLTWH(
      start,
      artwork.textCenter.dy - artwork.face.height / 4,
      fitted,
      artwork.face.height / 2,
    );
  }

  @override
  Widget build(BuildContext context) {
    final artwork = widget.artwork;
    final onTap = widget.onTap;
    final labelStyle = RewindTextStyles.body(
      artwork.textSize,
      color: artwork.color,
      height: 1.1,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedScale(
          scale: _pressed ? 0.95 : 1,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: ExcludeSemantics(
            child: Stack(
              fit: StackFit.expand,
              children: [
                RewindSvg(artwork.asset, fit: BoxFit.fill),
                Positioned.fromRect(
                  rect: artwork.icon,
                  child: HugeIcon(
                    icon: widget.icon,
                    size: artwork.icon.width,
                    color: artwork.color,
                    strokeWidth: artwork.iconStroke,
                  ),
                ),
                Positioned.fromRect(
                  rect: _labelRect(
                    labelStyle,
                    MediaQuery.textScalerOf(context),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(widget.label, style: labelStyle),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned.fromRect(
          rect: artwork.face,
          child: Semantics(
            button: onTap != null,
            label: widget.label,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: onTap == null,
              onTapDown: onTap == null ? null : (_) => _press(true),
              onTapUp: onTap == null ? null : (_) => _press(false),
              onTapCancel: onTap == null ? null : () => _press(false),
              onTap: onTap ?? () {},
            ),
          ),
        ),
      ],
    );
  }
}
