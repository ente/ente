import "dart:async";

import "package:ente_components/ente_components.dart";
import "package:ente_legacy/services/emergency_service.dart";
import "package:ente_legacy/services/legacy_kit_service.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:locker/l10n/l10n.dart";
import "package:locker/services/local_settings.dart";
import "package:locker/ui/utils/legacy_utils.dart";
import "package:logging/logging.dart";

const _titleStyle = TextStyle(
  fontFamily: TextStyles.outfitFontFamily,
  package: TextStyles.fontPackage,
  fontWeight: FontWeight.w600,
  fontSize: 18,
  height: 32 / 18,
);

const _descriptionStyle = TextStyle(
  fontFamily: TextStyles.fontFamily,
  package: TextStyles.fontPackage,
  fontWeight: FontWeight.w600,
  fontSize: 10,
  height: 14 / 10,
  letterSpacing: -0.2,
);

const _buttonStyle = TextStyle(
  fontFamily: TextStyles.outfitFontFamily,
  package: TextStyles.fontPackage,
  fontWeight: FontWeight.w600,
  fontSize: 10,
);

class LegacySetupBanner extends StatefulWidget {
  const LegacySetupBanner({super.key});

  @override
  State<LegacySetupBanner> createState() => _LegacySetupBannerState();
}

class _LegacySetupBannerState extends State<LegacySetupBanner> {
  static const _illustrationWidth = 155.0;
  static const _contentRightReserve = 150.0;

  final _logger = Logger("LegacySetupBanner");
  bool _shouldShow = false;

  @override
  void initState() {
    super.initState();
    unawaited(_evaluateVisibility());
  }

  Future<void> _evaluateVisibility() async {
    if (LocalSettings.instance.isLegacySetupBannerDismissed) {
      _setShouldShow(false);
      return;
    }
    try {
      final info = await EmergencyContactService.instance.getInfo();
      final legacyConfigured =
          info.contacts.isNotEmpty || await _hasLegacyKit();
      if (!mounted) return;
      _setShouldShow(!legacyConfigured);
    } catch (e, s) {
      _logger.warning("Failed to fetch legacy info for banner", e, s);
    }
  }

  void _setShouldShow(bool value) {
    if (!mounted || _shouldShow == value) return;
    setState(() => _shouldShow = value);
  }

  Future<bool> _hasLegacyKit() async {
    if (!LegacyKitService.instance.isInitialized) return false;
    try {
      final kits = await LegacyKitService.instance.getKits();
      return kits.isNotEmpty;
    } catch (e, s) {
      _logger.warning("Failed to fetch legacy kits for banner", e, s);
      return false;
    }
  }

  void _onSetup() {
    unawaited(openLegacyPage(context));
  }

  Future<void> _onDismiss() async {
    setState(() => _shouldShow = false);
    await LocalSettings.instance.setLegacySetupBannerDismissed(true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_shouldShow) return const SizedBox.shrink();
    final colors = context.componentColors;
    final l10n = context.l10n;

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Padding(
        padding: const EdgeInsets.only(bottom: Spacing.xl),
        child: GestureDetector(
          onTap: _onSetup,
          child: Container(
            width: double.infinity,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -8,
                  bottom: -8,
                  child: IgnorePointer(
                    child: Image.asset(
                      "assets/legacy_banner.png",
                      width: _illustrationWidth,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    17,
                    20,
                    _contentRightReserve,
                    19,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.shareYourLegacyBannerTitle,
                        style: _titleStyle.copyWith(color: colors.specialWhite),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.shareYourLegacyBannerDescription,
                        style: _descriptionStyle.copyWith(
                          color: colors.specialWhite.withValues(alpha: 0.79),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SetupButton(label: l10n.setupLegacy, onTap: _onSetup),
                    ],
                  ),
                ),
                Positioned(
                  top: 18,
                  right: 16,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _onDismiss,
                    child: HugeIcon(
                      icon: HugeIcons.strokeRoundedCancel01,
                      color: colors.specialWhite,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SetupButton extends StatelessWidget {
  const _SetupButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
        decoration: BoxDecoration(
          color: context.componentColors.specialWhite,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label, style: _buttonStyle.copyWith(color: Colors.black)),
      ),
    );
  }
}
