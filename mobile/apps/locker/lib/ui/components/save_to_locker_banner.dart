import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:locker/l10n/l10n.dart";

const _bannerHeight = 147.0;
const _illustrationWidth = 198.0;
const _illustrationHeight = 115.0;
const _duckyWidth = 193.0;
const _contentLeftInset = 25.0;
const _contentRightReserve = 200.0;
const _brandName = "Locker";

const _titleStyle = TextStyle(
  fontFamily: TextStyles.outfitFontFamily,
  package: TextStyles.fontPackage,
  fontWeight: FontWeight.w600,
  fontSize: 24,
  height: 24 / 24,
  letterSpacing: -0.72,
);

class SaveToLockerBanner extends StatelessWidget {
  const SaveToLockerBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Container(
        width: double.infinity,
        height: _bannerHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.primary,
          borderRadius: BorderRadius.circular(Radii.button),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: SvgPicture.asset(
                "assets/svg/save_to_locker_glyph.svg",
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: SizedBox(
                width: _illustrationWidth,
                height: _illustrationHeight,
                child: Stack(
                  children: [
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Image.asset(
                        "assets/save_to_locker_ducky.png",
                        width: _duckyWidth,
                        height: _illustrationHeight,
                      ),
                    ),
                    Positioned.fill(
                      child: SvgPicture.asset(
                        "assets/svg/save_to_locker_stars.svg",
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(
                  left: _contentLeftInset,
                  right: _contentRightReserve,
                ),
                child: Text.rich(
                  _titleSpan(
                    context.l10n.saveToLocker,
                    _titleStyle.copyWith(color: colors.specialWhite),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  TextSpan _titleSpan(String title, TextStyle style) {
    final brandIndex = title.indexOf(_brandName);
    if (brandIndex < 0) {
      return TextSpan(text: title, style: style);
    }
    return TextSpan(
      style: style,
      children: [
        TextSpan(text: title.substring(0, brandIndex)),
        const TextSpan(
          text: _brandName,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        TextSpan(text: title.substring(brandIndex + _brandName.length)),
      ],
    );
  }
}
