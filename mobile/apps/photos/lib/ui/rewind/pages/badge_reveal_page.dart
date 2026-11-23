import "dart:math";

import "package:flutter/material.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/shell/rewind_page.dart";
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
        "A person who regularly photographs sunrises, sunsets, and golden-hour light.",
  ),
  rust.RewindBadge.consistencyChamp => (
    title: "CONSISTENCY\nCHAMP",
    pronunciation: "/kən-ˈsis-tən-sē champ/",
    definition: "A person who takes photos consistently throughout the year.",
  ),
  rust.RewindBadge.unpaidPhotographer => (
    title: "UNPAID\nPHOTOGRAPHER",
    pronunciation: "/ən-ˈpād fə-ˈtä-grə-fər/",
    definition:
        "A person who frequently creates and shares photo albums with others.",
  ),
  rust.RewindBadge.mainCharacter => (
    title: "MAIN\nCHARACTER",
    pronunciation: "/ˈmān ˈker-ik-tər/",
    definition:
        "A person who appears in a significant proportion of their own photos.",
  ),
  rust.RewindBadge.earlyBird => (
    title: "EARLY BIRD",
    pronunciation: "/ˈər-lē ˈbərd/",
    definition:
        "A person who frequently takes photos during the early morning hours.",
  ),
  rust.RewindBadge.nightOwl => (
    title: "NIGHT OWL",
    pronunciation: "/ˈnīt ˌau̇l/",
    definition: "A person who frequently takes photos after dark.",
  ),
  rust.RewindBadge.weekendStar => (
    title: "WEEKEND STAR",
    pronunciation: "/ˈwēk-end ˈstär/",
    definition: "A person who takes most of their photos on weekends.",
  ),
  rust.RewindBadge.pawparazzi => (
    title: "PAWPARAZZI",
    pronunciation: "/ˌpȯ-pə-ˈrät-sē/",
    definition:
        "A person whose photo collection contains a high proportion of pet photographs.",
  ),
  rust.RewindBadge.foodie => (
    title: "FOODIE",
    pronunciation: "/ˈfü-dē/",
    definition:
        "A person who frequently photographs food, meals, and dining experiences.",
  ),
  rust.RewindBadge.plantParent => (
    title: "PLANT PARENT",
    pronunciation: "/ˈplant ˌper-ənt/",
    definition:
        "A person who regularly photographs plants, flowers, and other botanical subjects.",
  ),
  rust.RewindBadge.buildingBuff => (
    title: "BUILDING BUFF",
    pronunciation: "/ˈbil-diŋ ˈbəf/",
    definition:
        "A person who frequently photographs buildings, architecture, and structural details.",
  ),
  rust.RewindBadge.screenshotCollector => (
    title: "SCREENSHOT\nCOLLECTOR",
    pronunciation: "/ˈskrēn-ˌshät kə-ˈlek-tər/",
    definition:
        "A person who regularly saves screenshots of information, conversations, images, and other digital content.",
  ),
  rust.RewindBadge.hobbyHopper => (
    title: "HOBBY HOPPER",
    pronunciation: "/ˈhä-bē ˈhä-pər/",
    definition:
        "A person whose photographs reflect a variety of hobbies and interests over time.",
  ),
  rust.RewindBadge.indoorKid => (
    title: "INDOOR KID",
    pronunciation: "/ˈin-dȯr ˈkid/",
    definition: "A person who takes most of their photographs indoors.",
  ),
  rust.RewindBadge.outOfOffice => (
    title: "OUT OF OFFICE",
    pronunciation: "/ˈau̇t əv ˈȯ-fəs/",
    definition:
        "A person who frequently photographs travel, outings, and visits to different places.",
  ),
  rust.RewindBadge.fullThrottle => (
    title: "FULL THROTTLE",
    pronunciation: "/ˈfu̇l ˈthrä-tᵊl/",
    definition:
        "A person who regularly captures sports, exercise, and other physical activities.",
  ),
  rust.RewindBadge.eventHopper => (
    title: "EVENT HOPPER",
    pronunciation: "/i-ˈvent ˈhä-pər/",
    definition:
        "A person who frequently photographs parties, concerts, festivals, celebrations, and other events.",
  ),
  rust.RewindBadge.alwaysRolling => (
    title: "ALWAYS\nROLLING",
    pronunciation: "/ˈȯl-wāz ˈrō-liŋ/",
    definition:
        "A person who frequently records videos rather than taking still photographs.",
  ),
  rust.RewindBadge.fitCheck => (
    title: "FIT CHECK",
    pronunciation: "/ˈfit ˌchek/",
    definition:
        "A person who regularly photographs clothing, outfits, footwear, and accessories.",
  ),
  rust.RewindBadge.artLover => (
    title: "ART LOVER",
    pronunciation: "/ˈärt ˈlə-vər/",
    definition:
        "A person who frequently photographs paintings, sculptures, murals, and other forms of art.",
  ),
  rust.RewindBadge.limitedEdition => (
    title: "LIMITED\nEDITION",
    pronunciation: "/ˈli-mə-təd i-ˈdi-shən/",
    definition:
        "A person who takes relatively few photos, spread across a substantial part of the year.",
  ),
  rust.RewindBadge.happySnapper => (
    title: "HAPPY SNAPPER",
    pronunciation: "/ˈha-pē ˈsna-pər/",
    definition:
        "A person who takes many photos across a wide variety of subjects, without a single dominant interest.",
  ),
  rust.RewindBadge.openingCredits => (
    title: "OPENING\nCREDITS",
    pronunciation: "/ˈō-pə-niŋ ˈkre-dits/",
    definition:
        "A person whose available photo history covers only a short period of time.",
  ),
  rust.RewindBadge.guestStar => (
    title: "GUEST STAR",
    pronunciation: "/ˈgest ˌstär/",
    definition:
        "A person who takes photos in occasional bursts, with extended periods of little or no activity.",
  ),
  rust.RewindBadge.mixedBag => (
    title: "MIXED BAG",
    pronunciation: "/ˈmikst ˈbag/",
    definition:
        "A person whose photo collection does not show a clearly dominant pattern or contains insufficient information to identify one.",
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
                    visible: RewindShareable.capturing(context),
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
                                  31.685,
                                  color: RewindColors.white,
                                  height: 1,
                                  letterSpacing: 0.6337,
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
