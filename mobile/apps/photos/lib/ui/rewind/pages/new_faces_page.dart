import "dart:math";

import "package:flutter/material.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/story/rewind_face.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_elapsed.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_numbers.dart";
import "package:photos/ui/rewind/widgets/rewind_reveal_layer.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

typedef _Bubble = ({
  double size,
  Offset center,
  int delayMs,
  Offset drift,
  int periodMs,
  double phase,
});

const List<_Bubble> _bubbles = [
  (
    size: 169.2,
    center: Offset(165.6, 344.6),
    delayMs: 150,
    drift: Offset(0, -7),
    periodMs: 4200,
    phase: 0,
  ),
  (
    size: 141.2,
    center: Offset(300.6, 269.6),
    delayMs: 330,
    drift: Offset(-5, -6),
    periodMs: 4700,
    phase: 0.6,
  ),
  (
    size: 129.2,
    center: Offset(300.6, 412.6),
    delayMs: 420,
    drift: Offset(4, 6),
    periodMs: 3900,
    phase: 0.2,
  ),
  (
    size: 113.2,
    center: Offset(140.6, 204.6),
    delayMs: 240,
    drift: Offset(5, -5),
    periodMs: 3600,
    phase: 0.35,
  ),
  (
    size: 101.2,
    center: Offset(60.6, 434.6),
    delayMs: 510,
    drift: Offset(-6, -4),
    periodMs: 4400,
    phase: 0.75,
  ),
  (
    size: 89.2,
    center: Offset(180.6, 484.6),
    delayMs: 600,
    drift: Offset(5, -6),
    periodMs: 3400,
    phase: 0.5,
  ),
];

const _paintOrder = [3, 1, 0, 4, 2, 5];

class NewFacesPage extends RewindPage {
  const NewFacesPage(this.newFaces, this.faces);

  final rust.NewFaces newFaces;
  final List<RewindFace> faces;

  @override
  String get key => "new_faces";

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final count = newFaces.count;
    final title = count == 1 ? "1 NEW FACE" : "${rewindCount(count)} NEW FACES";
    const line = "debuted in your frame this year.";
    final shown = min(faces.length, _bubbles.length);
    return RewindShareable(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RewindBackdrop(
            color: Color(0xFF19B331),
            pattern: RewindStripes(Color(0xFF19BA32)),
          ),
          Semantics(
            label: "${title.toLowerCase()} $line",
            child: ExcludeSemantics(
              child: RewindStage(
                children: [
                  Positioned.fill(
                    child: RewindLeave(
                      position: position,
                      centerY: 345,
                      child: RewindElapsed(
                        active: isActive,
                        builder: (context, ms) => Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (final slot in _paintOrder)
                              if (slot < shown)
                                _placed(
                                  _bubbles[slot],
                                  faces[slot],
                                  ms,
                                  isActive,
                                ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  RewindRevealLayer(
                    left: 22,
                    top: 630,
                    maxWidth: 346,
                    height: 54,
                    position: position,
                    active: isActive,
                    preset: RewindPreset.slap,
                    delayMs: 1050,
                    child: RewindOutlinedText(
                      title,
                      style: RewindTextStyles.display(
                        57.019,
                        color: RewindColors.white,
                      ),
                      outline: 2.17,
                      shadow: const Offset(3.1, 3.72),
                    ),
                  ),
                  RewindRevealLayer(
                    left: 28,
                    top: 702,
                    width: 316,
                    height: 22,
                    position: position,
                    active: isActive,
                    delayMs: 1350,
                    child: Text(line, style: RewindTextStyles.body(17)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placed(_Bubble bubble, RewindFace face, double ms, bool isActive) {
    final since = ms - bubble.delayMs - 700;
    var offset = Offset.zero;
    if (since > 0) {
      final cycle = (since / bubble.periodMs + bubble.phase) % 1;
      final swing = Curves.easeInOut.transform(1 - (2 * cycle - 1).abs());
      final ramp = min(1.0, since / 600);
      offset = bubble.drift * swing * ramp;
    }
    return Positioned.fromRect(
      rect: Rect.fromCenter(
        center: bubble.center,
        width: bubble.size,
        height: bubble.size,
      ),
      child: Transform.translate(
        offset: offset,
        child: RewindEntrance(
          preset: RewindPreset.bubble,
          active: isActive,
          delayMs: bubble.delayMs,
          child: _FaceBubble(face),
        ),
      ),
    );
  }
}

class _FaceBubble extends StatelessWidget {
  const _FaceBubble(this.face);

  final RewindFace face;

  @override
  Widget build(BuildContext context) {
    final crop = face.crop;
    final initial = face.name?.trim().characters.firstOrNull ?? "";
    return CustomPaint(
      painter: const _BubblePainter(),
      child: Padding(
        padding: const EdgeInsets.all(6.6),
        child: ClipOval(
          child: crop != null
              ? Image.memory(crop, fit: BoxFit.cover, gaplessPlayback: true)
              : ColoredBox(
                  color: RewindColors.cream,
                  child: Center(
                    child: Text(
                      initial.toUpperCase(),
                      style: RewindTextStyles.display(
                        40,
                        color: RewindColors.ink,
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  const _BubblePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final ink = Paint()..color = RewindColors.ink;
    canvas.drawCircle(center + const Offset(5.28, 6.6), radius, ink);
    canvas.drawCircle(center, radius, ink);
    canvas.drawCircle(center, radius - 3, Paint()..color = RewindColors.white);
  }

  @override
  bool shouldRepaint(_BubblePainter oldDelegate) => false;
}
