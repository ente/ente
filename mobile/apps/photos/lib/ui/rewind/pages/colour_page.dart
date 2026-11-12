import "package:flutter/material.dart";
import "package:photos/models/file/file.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/story/rewind_colours.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_layer.dart";
import "package:photos/ui/rewind/widgets/rewind_photo.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

class ColourPage extends RewindPage {
  const ColourPage(this.colour, this.photos);

  static const pageKey = "colour";

  static const _columns = [105.79, 105.79, 104.79];
  static const _rowHeight = 138.725;

  final rust.ColourOfTheYear colour;
  final List<EnteFile> photos;

  @override
  String get key => pageKey;

  @override
  RewindChrome get chrome => RewindChrome(
    foreground: colour.colour.text,
    wordmark: colour.colour.text == RewindColors.ink
        ? RewindColors.ink
        : RewindColors.white,
  );

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final look = colour.colour;
    return RewindShareable(
      child: Stack(
        fit: StackFit.expand,
        children: [
          RewindBackdrop(
            color: look.color,
            pattern: RewindStripes(look.stripe),
          ),
          RewindStage(
            children: [
              RewindLayer(
                rect: const Rect.fromLTWH(25, 125, 340, 546.9),
                position: position,
                child: RewindEntrance(
                  preset: RewindPreset.flip,
                  active: isActive,
                  child: _card(look, isActive),
                ),
              ),
              RewindLayer(
                rect: const Rect.fromLTWH(28, 705, 316, 52),
                position: position,
                child: RewindEntrance(
                  preset: RewindPreset.line,
                  active: isActive,
                  delayMs: 800,
                  child: Text(
                    "${colour.percent}% of your photos were mostly "
                    "${look.word}.",
                    style: RewindTextStyles.body(
                      19,
                      height: 1.32,
                      color: look.text,
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

  Widget _card(rust.RewindColour look, bool isActive) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RewindColors.cream,
        borderRadius: BorderRadius.circular(23.05),
      ),
      child: Stack(
        children: [
          Positioned(
            left: 11.5,
            top: 11.5,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11.98),
              child: Column(
                children: [
                  for (var row = 0; row < 3; row++)
                    Row(
                      children: [
                        for (var column = 0; column < 3; column++)
                          SizedBox(
                            width: _columns[column],
                            height: _rowHeight,
                            child: _cell(row * 3 + column, look),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 19,
            top: 451,
            child: RewindFitWidth(
              width: 302,
              child: Text(
                look.label,
                style: RewindTextStyles.display(
                  32,
                  color: RewindColors.ink,
                  height: 1.15,
                ),
              ),
            ),
          ),
          Positioned(
            left: 19,
            top: 492,
            child: RewindEntrance(
              preset: RewindPreset.fadeIn,
              active: isActive,
              delayMs: 700,
              child: Text(
                look.hex,
                style: const TextStyle(
                  fontFamily: "Inter",
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: Color(0xFF5C5C5C),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(int index, rust.RewindColour look) {
    if (photos.isEmpty) return ColoredBox(color: look.stripe);
    return RewindPhoto(
      photos[index % photos.length],
      placeholder: Color.lerp(look.color, RewindColors.cream, 0.55)!,
    );
  }
}
