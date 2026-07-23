import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:photos/l10n/l10n.dart";
import "package:photos/models/rituals/ritual_models.dart";

const String _duckyShareArtAsset = "assets/rituals/ritual_ducky_share.svg";
const String _enteLogoAsset = "assets/ente_io_green_black.svg";

class RitualShareCard extends StatelessWidget {
  const RitualShareCard({
    super.key,
    required this.ritual,
    required this.progress,
  });

  final Ritual ritual;
  final RitualProgress? progress;

  static const double width = 360;
  static const double height = 640;
  static const _duckyShareAspectRatio = 353 / 574;

  static Future<void> precacheAssets(BuildContext context) async {
    await Future.wait<void>([
      const SvgAssetLoader(_duckyShareArtAsset).loadBytes(context),
      const SvgAssetLoader(_enteLogoAsset).loadBytes(context),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final title = ritual.title.isEmpty
        ? context.l10n.ritualUntitled
        : ritual.title;
    final streak = progress?.currentStreak ?? 0;

    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            children: [
              _RitualShareHeader(icon: ritual.icon, title: title),
              const SizedBox(height: 16),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: AspectRatio(
                    aspectRatio: _duckyShareAspectRatio,
                    child: _RitualDuckyShareArt(streak: streak),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              SvgPicture.asset(_enteLogoAsset, height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _RitualShareHeader extends StatelessWidget {
  const _RitualShareHeader({required this.icon, required this.title});

  final String icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F3F3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            icon,
            style: const TextStyle(
              fontSize: 20,
              decoration: TextDecoration.none,
              height: 1,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: "Inter",
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Color(0xFF232323),
              decoration: TextDecoration.none,
              height: 1.1,
            ),
          ),
        ),
      ],
    );
  }
}

class _RitualDuckyShareArt extends StatelessWidget {
  const _RitualDuckyShareArt({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    final streakText = streak.toString();
    final fontSize = _streakFontSize(streakText);
    final textStyle = TextStyle(
      fontFamily: "Nunito",
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      color: Colors.white,
      decoration: TextDecoration.none,
      height: 1,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textHeight = _measureTextHeight(
          text: streakText,
          style: textStyle,
          maxWidth: constraints.maxWidth,
        );
        final top = (constraints.maxHeight * 0.24) - (textHeight / 2);

        return Stack(
          fit: StackFit.expand,
          children: [
            SvgPicture.asset(_duckyShareArtAsset, fit: BoxFit.cover),
            Positioned(
              top: top,
              left: 0,
              right: 0,
              child: Text(
                streakText,
                textAlign: TextAlign.center,
                style: textStyle,
              ),
            ),
          ],
        );
      },
    );
  }
}

double _streakFontSize(String text) {
  switch (text.length) {
    case 1:
      return 140;
    case 2:
      return 110;
    default:
      return 80;
  }
}

double _measureTextHeight({
  required String text,
  required TextStyle style,
  required double maxWidth,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
    maxLines: 1,
  )..layout(maxWidth: maxWidth);
  return painter.height;
}
