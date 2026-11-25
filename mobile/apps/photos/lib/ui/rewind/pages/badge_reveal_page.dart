import "dart:math";

import "package:flutter/material.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_page_scope.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_motion.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_rive.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_svg.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

typedef _BadgeCopy = ({String title, String pronunciation, String definition});

_BadgeCopy _copyOf(rust.RewindBadge badge) => switch (badge) {
  rust.RewindBadge.sunChaser => (
    title: "SUN CHASER",
    pronunciation: "/ˈsən ˌchā-sər/",
    definition:
        "Someone who regularly photographs sunrises, sunsets, and the golden-hour light.",
  ),
  rust.RewindBadge.consistencyChamp => (
    title: "CONSISTENCY\nCHAMP",
    pronunciation: "/kən-ˈsis-tən-sē champ/",
    definition:
        "Someone who showed up for their camera roll every single month. Come rain or shine.",
  ),
  rust.RewindBadge.unpaidPhotographer => (
    title: "UNPAID\nPHOTOGRAPHER",
    pronunciation: "/ən-ˈpād fə-ˈtä-grə-fər/",
    definition: "The reason the group chat has any photos at all.",
  ),
  rust.RewindBadge.mainCharacter => (
    title: "MAIN\nCHARACTER",
    pronunciation: "/ˈmān ˈker-ik-tər/",
    definition:
        "Someone who loves being photographed. Every scene was better with them in it.",
  ),
  rust.RewindBadge.earlyBird => (
    title: "EARLY BIRD",
    pronunciation: "/ˈər-lē ˈbərd/",
    definition: "Someone who’s up before the alarm and out before the crowds.",
  ),
  rust.RewindBadge.nightOwl => (
    title: "NIGHT OWL",
    pronunciation: "/ˈnīt ˌau̇l/",
    definition: "Someone whose camera has a thriving nightlife.",
  ),
  rust.RewindBadge.weekendStar => (
    title: "WEEKEND STAR",
    pronunciation: "/ˈwēk-end ˈstär/",
    definition: "Monday to Friday is rehearsal. The weekend is showtime.",
  ),
  rust.RewindBadge.pawparazzi => (
    title: "PAWPARAZZI",
    pronunciation: "/ˌpȯ-pə-ˈrät-sē/",
    definition:
        "Someone whose pet has had more photoshoots than most celebrities.",
  ),
  rust.RewindBadge.foodie => (
    title: "FOODIE",
    pronunciation: "/ˈfü-dē/",
    definition: "Someone whose phone always eats first.",
  ),
  rust.RewindBadge.plantParent => (
    title: "PLANT PARENT",
    pronunciation: "/ˈplant ˌper-ənt/",
    definition:
        "Someone who stops for every bloom and says hello to every leaf.",
  ),
  rust.RewindBadge.buildingBuff => (
    title: "BUILDING BUFF",
    pronunciation: "/ˈbil-diŋ ˈbəf/",
    definition: "Someone who sees art in arches, stairs and skylines.",
  ),
  rust.RewindBadge.screenshotCollector => (
    title: "SCREENSHOT\nCOLLECTOR",
    pronunciation: "/ˈskrēn-ˌshät kə-ˈlek-tər/",
    definition:
        "The keeper of receipts, recipes and every chat worth remembering.",
  ),
  rust.RewindBadge.hobbyHopper => (
    title: "HOBBY HOPPER",
    pronunciation: "/ˈhä-bē ˈhä-pər/",
    definition:
        "Jack of all trades, master of fun. A new passion every few months.",
  ),
  rust.RewindBadge.indoorKid => (
    title: "INDOOR KID",
    pronunciation: "/ˈin-dȯr ˈkid/",
    definition:
        "Someone who has mastered the art of cozy. The best moments happen at home, with the best people.",
  ),
  rust.RewindBadge.outOfOffice => (
    title: "OUT OF OFFICE",
    pronunciation: "/ˈau̇t əv ˈȯ-fəs/",
    definition: "Explorer whose suitcase barely got unpacked this year.",
  ),
  rust.RewindBadge.fullThrottle => (
    title: "FULL THROTTLE",
    pronunciation: "/ˈfu̇l ˈthrä-tᵊl/",
    definition:
        "Someone who doesn’t do “sit still”. If there’s a game, a trail or a finish line, they’re there.",
  ),
  rust.RewindBadge.eventHopper => (
    title: "EVENT HOPPER",
    pronunciation: "/i-ˈvent ˈhä-pər/",
    definition:
        "The friend with the best calendar. If it was happening, they were there.",
  ),
  rust.RewindBadge.alwaysRolling => (
    title: "ALWAYS\nROLLING",
    pronunciation: "/ˈȯl-wāz ˈrō-liŋ/",
    definition:
        "Someone who shoots more videos than photos, every frame is priceless.",
  ),
  rust.RewindBadge.fitCheck => (
    title: "FIT CHECK",
    pronunciation: "/ˈfit ˌchek/",
    definition:
        "Someone who never wastes a good outfit. Every look gets documented.",
  ),
  rust.RewindBadge.artLover => (
    title: "ART LOVER",
    pronunciation: "/ˈärt ˈlə-vər/",
    definition:
        "Someone who finds art everywhere, from galleries to street corners.",
  ),
  rust.RewindBadge.limitedEdition => (
    title: "LIMITED\nEDITION",
    pronunciation: "/ˈli-mə-təd i-ˈdi-shən/",
    definition: "Someone who doesn’t snap everything, just the good stuff.",
  ),
  rust.RewindBadge.happySnapper => (
    title: "HAPPY SNAPPER",
    pronunciation: "/ˈha-pē ˈsna-pər/",
    definition:
        "Someone who photographs everything, because everything is worth it.",
  ),
  rust.RewindBadge.openingCredits => (
    title: "OPENING\nCREDITS",
    pronunciation: "/ˈō-pə-niŋ ˈkre-dits/",
    definition:
        "Someone whose story is just getting started. If this is the opening scene, the rest is going to be epic.",
  ),
  rust.RewindBadge.guestStar => (
    title: "GUEST STAR",
    pronunciation: "/ˈgest ˌstär/",
    definition:
        "Someone who saves their camera for the moments that matter, then goes all in.",
  ),
  rust.RewindBadge.mixedBag => (
    title: "MIXED BAG",
    pronunciation: "/ˈmikst ˈbag/",
    definition: "Impossible to label, and that’s the best part.",
  ),
};

class BadgeRevealPage extends RewindPage {
  const BadgeRevealPage(this.badge);

  static const backdrop = RewindBackdrop(
    color: Color(0xFF1A1A1A),
    pattern: RewindRays(Color(0xFF232323), center: Offset(195, 354)),
  );
  static const _badgeCenter = Offset(195, 378.3);
  static const _sparkles = [
    (RewindAssets.topBadgeSparkle, Offset(318, 217), 900),
    (RewindAssets.bottomBadgeSparkle, Offset(25, 502), 1050),
  ];

  final rust.Badge badge;

  @override
  String get key => "badge";

  @override
  Duration? get reelHold =>
      const Duration(milliseconds: 3400 + RewindMotion.reelReadingMs);

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final copy = _copyOf(badge.id);
    final title = copy.title.replaceAll("\n", " ");
    final trigger = badge.id.name.replaceAllMapped(
      RegExp("[A-Z]"),
      (match) => "_${match[0]!.toLowerCase()}",
    );
    final inset =
        MediaQuery.paddingOf(context).bottom /
        RewindStage.scaleFor(MediaQuery.sizeOf(context));
    return RewindShareable(
      child: Stack(
        fit: StackFit.expand,
        children: [
          backdrop,
          RewindStage(
            children: [
              Positioned.fromRect(
                rect: Rect.fromCenter(
                  center: const Offset(195, 376),
                  width: 280,
                  height: 380,
                ),
                child: RewindLeave(
                  position: position,
                  centerY: 376,
                  child: RewindEntrance(
                    preset: RewindPreset.fadeIn,
                    active: isActive,
                    delayMs: 200,
                    child: const CustomPaint(painter: _GlowPainter()),
                  ),
                ),
              ),
              for (final (asset, at, delayMs) in _sparkles)
                Positioned(
                  left: at.dx,
                  top: at.dy,
                  child: RewindLeave(
                    position: position,
                    centerY: at.dy,
                    child: RewindEntrance(
                      preset: RewindPreset.twinkle,
                      active: isActive,
                      delayMs: delayMs,
                      child: RewindIdleLoop(
                        idle: RewindIdle.twinkle,
                        active: isActive,
                        delayMs: delayMs + 900,
                        child: RewindSvg(asset),
                      ),
                    ),
                  ),
                ),
              Positioned.fromRect(
                rect: Rect.fromCenter(
                  center: _badgeCenter,
                  width: 304,
                  height: 382,
                ),
                child: RewindLeave(
                  position: position,
                  centerY: _badgeCenter.dy,
                  child: Semantics(
                    label: "$title badge",
                    button: true,
                    hint: "Double tap to flip it again",
                    child: OverflowBox(
                      maxWidth: 547.4,
                      maxHeight: 608.2,
                      child: RewindBadge(badge: trigger, active: isActive),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 33,
                top: 109,
                width: 324,
                child: Builder(
                  builder: (context) => Visibility(
                    visible:
                        RewindShareable.capturing(context) ||
                        RewindPageScope.reelOf(context),
                    maintainState: true,
                    maintainAnimation: true,
                    maintainSize: true,
                    child: RewindLeave(
                      position: position,
                      centerY: 141,
                      child: Semantics(
                        header: true,
                        label: "What my photos say about me",
                        child: ExcludeSemantics(
                          child: RewindEntrance(
                            preset: RewindPreset.rise,
                            active: isActive,
                            child: RewindFitWidth(
                              width: 324,
                              alignment: Alignment.topCenter,
                              child: Text(
                                "WHAT MY PHOTOS\nSAY ABOUT ME",
                                textAlign: TextAlign.center,
                                style: RewindTextStyles.display(
                                  26,
                                  color: RewindColors.white,
                                  height: 1,
                                  letterSpacing: 0.52,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: RewindLeave(
                  position: position,
                  centerY: 640,
                  child: CustomSingleChildLayout(
                    delegate: _PlaqueLayout(bottom: 768 - max(0, inset - 12)),
                    child: Semantics(
                      label: "$title. ${copy.definition}",
                      child: ExcludeSemantics(
                        child: RewindEntrance(
                          preset: RewindPreset.slap,
                          active: isActive,
                          delayMs: 1350,
                          child: _Plaque(
                            pronunciation: "${copy.pronunciation} · noun",
                            definition: copy.definition,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlaqueLayout extends SingleChildLayoutDelegate {
  const _PlaqueLayout({required this.bottom});

  static const _top = 609.0;

  final double bottom;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    (size.width - childSize.width) / 2,
    min(_top, bottom - childSize.height),
  );

  @override
  bool shouldRelayout(_PlaqueLayout oldDelegate) =>
      oldDelegate.bottom != bottom;
}

class _Plaque extends StatelessWidget {
  const _Plaque({required this.pronunciation, required this.definition});

  static const _width = 314.0;
  static const _minHeight = 115.0;

  final String pronunciation;
  final String definition;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _PlaquePainter(),
      child: ConstrainedBox(
        constraints: const BoxConstraints.tightFor(
          width: _width,
        ).copyWith(minHeight: _minHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 13, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                pronunciation,
                textAlign: TextAlign.center,
                style: RewindTextStyles.phonetic(
                  12.5,
                  color: RewindColors.ink.withValues(alpha: 0.72),
                ).copyWith(fontWeight: FontWeight.w500, height: 1.26),
              ),
              const SizedBox(height: 1),
              Text(
                definition,
                textAlign: TextAlign.center,
                style: RewindTextStyles.body(
                  18,
                  height: 1.26,
                  color: RewindColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  const _GlowPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawOval(
      Offset.zero & size,
      Paint()
        ..color = RewindColors.white.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 64.4),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter oldDelegate) => false;
}

class _PlaquePainter extends CustomPainter {
  const _PlaquePainter();

  static const _gold = Color(0xFFFFCA39);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final plate = Path()
      ..moveTo(38, 0)
      ..lineTo(w - 38, 0)
      ..cubicTo(w - 26, 0, w - 16, 12.43, w - 14, 29.53)
      ..cubicTo(w - 6, 34.19, w, 45.07, w, h / 2)
      ..cubicTo(w, h - 45.07, w - 6, h - 34.19, w - 14, h - 29.53)
      ..cubicTo(w - 16, h - 12.43, w - 26, h, w - 38, h)
      ..lineTo(38, h)
      ..cubicTo(26, h, 16, h - 12.43, 14, h - 29.53)
      ..cubicTo(6, h - 34.19, 0, h - 45.07, 0, h / 2)
      ..cubicTo(0, 45.07, 6, 34.19, 14, 29.53)
      ..cubicTo(16, 12.43, 26, 0, 38, 0)
      ..close();
    canvas.drawPath(plate, Paint()..color = RewindColors.cream);
    canvas.drawPath(
      plate,
      Paint()
        ..color = _gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_PlaquePainter oldDelegate) => false;
}
