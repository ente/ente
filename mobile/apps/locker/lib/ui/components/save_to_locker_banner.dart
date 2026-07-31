import "dart:math" as math;

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:locker/l10n/l10n.dart";
import "package:rive/rive.dart" as rive;

const _bannerHeight = 147.0;
const _illustrationWidth = 220.0;
const _illustrationHeight = 128.0;
const _illustrationTilt = -3 * math.pi / 180;
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

class SaveToLockerBanner extends StatefulWidget {
  const SaveToLockerBanner({super.key});

  @override
  State<SaveToLockerBanner> createState() => _SaveToLockerBannerState();
}

class _SaveToLockerBannerState extends State<SaveToLockerBanner> {
  late final rive.FileLoader _illustrationLoader;

  @override
  void initState() {
    super.initState();
    _illustrationLoader = rive.FileLoader.fromAsset(
      "assets/save_to_locker.riv",
      riveFactory: rive.Factory.flutter,
    );
  }

  @override
  void dispose() {
    _illustrationLoader.dispose();
    super.dispose();
  }

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
              right: -18,
              bottom: -12,
              child: Transform.rotate(
                angle: _illustrationTilt,
                alignment: Alignment.bottomRight,
                child: SizedBox(
                  width: _illustrationWidth,
                  height: _illustrationHeight,
                  child: rive.RiveWidgetBuilder(
                    fileLoader: _illustrationLoader,
                    builder: (context, state) {
                      if (state is rive.RiveLoaded) {
                        return rive.RiveWidget(
                          controller: state.controller,
                          fit: rive.Fit.contain,
                        );
                      }
                      return const SizedBox.expand();
                    },
                  ),
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
