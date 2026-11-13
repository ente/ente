import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/notification_service.dart";
import "package:photos/ui/home/memories/horts.dart";
import "package:photos/ui/home/memories/memory_card_constants.dart";

class CraftingMemoriesCardWidget extends StatelessWidget {
  final double width;
  final double height;
  final Function(bool)? onShouldShowChanged;

  const CraftingMemoriesCardWidget({
    super.key,
    required this.width,
    required this.height,
    this.onShouldShowChanged,
  });

  static Future<bool> shouldShow() async {
    final hasPermissions = await NotificationService.instance
        .hasGrantedPermissions();
    if (hasPermissions) return false;
    final hasDismissed = await localSettings
        .getCraftingMemoriesBannerDismissed();
    return !hasDismissed;
  }

  Future<void> _onTap(BuildContext context) async {
    if (await NotificationService.instance.requestPermissions(context) &&
        context.mounted) {
      onShouldShowChanged?.call(false);
    }
  }

  Future<void> _onDismissTap(BuildContext context) async {
    await localSettings.setCraftingMemoriesBannerDismissed();
    if (!context.mounted) return;
    onShouldShowChanged?.call(false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.strings;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: kMemoryCardStripGap / 2.0,
      ),
      child: SizedBox(
        height: height,
        width: width,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(kMemoryCardBorderRadius),
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => _onTap(context),
                  child: Stack(
                    children: [
                      const Positioned.fill(child: Horts()),
                      Padding(
                        padding: EdgeInsets.all(width * 0.125),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.craftingMemoriesFirstHalf,
                              textScaler: .noScaling,
                              style: TextStyle(
                                fontFamily: TextStyles.outfitFontFamily,
                                package: TextStyles.fontPackage,
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: width * 0.115,
                                height: 1,
                              ),
                            ),
                            Text(
                              l10n.craftingMemoriesSecondHalf,
                              textScaler: .noScaling,
                              style: TextStyle(
                                fontFamily: "Gochi Hand",
                                package: TextStyles.fontPackage,
                                color: Colors.white,
                                fontSize: width * 0.175,
                                height: 1,
                              ),
                            ),
                            const SizedBox(height: 6),
                            DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white.withAlpha(64),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: width * 0.125,
                                  vertical: width * 0.075,
                                ),
                                child: Text(
                                  l10n.notifyMe,
                                  textScaler: .noScaling,
                                  style: TextStyle(
                                    fontFamily: TextStyles.outfitFontFamily,
                                    package: TextStyles.fontPackage,
                                    color: Colors.white,
                                    fontSize: width * 0.11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: Tooltip(
                  message: l10n.close,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _onDismissTap(context),
                    child: Padding(
                      padding: EdgeInsets.all(width * 0.08),
                      child: SizedBox.square(
                        dimension: 16,
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            color: Color(0x4AFFFFFF),
                            shape: BoxShape.circle,
                          ),
                          child: Transform.scale(
                            scale: 0.75,
                            child: const HugeIcon(
                              icon: HugeIcons.strokeRoundedCancel01,
                              color: Colors.white,
                              strokeWidth: 1.0 / 0.75,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
