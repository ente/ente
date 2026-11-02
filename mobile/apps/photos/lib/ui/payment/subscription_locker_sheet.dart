import "dart:math" as math;

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:hugeicons/hugeicons.dart";
import "package:url_launcher/url_launcher_string.dart";

Future<void> showSubscriptionLockerSheet(BuildContext context) {
  return showBottomSheetComponent<void>(
    context: context,
    builder: (_) => const SubscriptionLockerSheet(),
  );
}

class SubscriptionLockerSheet extends StatelessWidget {
  const SubscriptionLockerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final mediaQuery = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = constraints.maxWidth / 375;
        final height = math.min(
          642 * scale,
          mediaQuery.size.height - mediaQuery.padding.top,
        );
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Radii.bottomSheet),
          ),
          child: Material(
            color: colors.blue,
            child: SizedBox(
              height: height,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: ShaderMask(
                        blendMode: BlendMode.dstIn,
                        shaderCallback: (bounds) =>
                            LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                colors.specialWhite.withValues(alpha: 0.28),
                              ],
                            ).createShader(
                              Rect.fromLTRB(
                                0,
                                (287.5 - 33) * scale,
                                bounds.width,
                                (922 - 33) * scale,
                              ),
                            ),
                        child: Stack(
                          children: [
                            Positioned(
                              top: -33 * scale,
                              left: -67 * scale,
                              width: 745 * scale,
                              height: 1066 * scale,
                              child: SvgPicture.asset(
                                "assets/onboarding_doodle.svg",
                                excludeFromSemantics: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 198 * scale,
                    left: -93 * scale,
                    child: Container(
                      width: 530 * scale,
                      height: 530 * scale,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF73B8FF).withValues(alpha: 0.5),
                            const Color(0x001A73FF),
                          ],
                          stops: const [0.423739, 1],
                        ),
                      ),
                    ),
                  ),
                  SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: height),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              Spacing.xxl,
                              36,
                              Spacing.xxl,
                              0,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    SvgPicture.asset(
                                      "assets/subscription/locker_wordmark.svg",
                                      width: 59.2,
                                      height: 40,
                                      semanticsLabel:
                                          context.strings.enteLocker,
                                    ),
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: colors.specialWhite.withValues(
                                          alpha: 0.22,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: IconButtonComponent(
                                        variant:
                                            IconButtonComponentVariant.unfilled,
                                        size: 44,
                                        icon: HugeIcon(
                                          icon: HugeIcons.strokeRoundedCancel01,
                                          size: 20,
                                          color: colors.specialWhite,
                                        ),
                                        tooltip: context.strings.close,
                                        onTap: () =>
                                            Navigator.of(context).pop(),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: Spacing.lg),
                                Text(
                                  context.strings.subscriptionLockerTitle,
                                  style: TextStyles.display1.copyWith(
                                    color: colors.specialWhite,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.7,
                                  ),
                                ),
                                const SizedBox(height: Spacing.sm),
                                Text(
                                  context.strings.subscriptionLockerDescription,
                                  style: TextStyles.body.copyWith(
                                    color: colors.specialWhite,
                                    fontSize: 15,
                                    height: 21 / 15,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Image.asset(
                              "assets/subscription/locker_phone.png",
                              width: 319.414 * scale,
                              height: 393.965 * scale,
                              excludeFromSemantics: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    right: Spacing.md,
                    bottom: math.max(14, mediaQuery.padding.bottom),
                    child: TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: colors.specialWhite,
                        backgroundColor: colors.specialScrim.withValues(
                          alpha: 0.22,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.md,
                          vertical: Spacing.xs,
                        ),
                        textStyle: TextStyles.mini.copyWith(height: 18 / 12),
                      ),
                      onPressed: () => launchUrlString(
                        "https://ente.com/locker",
                        mode: LaunchMode.externalApplication,
                      ),
                      child: Text(context.strings.subscriptionLearnMore),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
