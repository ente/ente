import "dart:async";

import "package:ente_components/theme/text_styles.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/service_locator.dart";
import "package:photos/theme/colors.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/components/banners/banner_action_button.dart";

class OfflineSettingsBanner extends StatefulWidget {
  final VoidCallback onGetStarted;

  const OfflineSettingsBanner({super.key, required this.onGetStarted});

  @override
  State<OfflineSettingsBanner> createState() => _OfflineSettingsBannerState();
}

class _OfflineSettingsBannerState extends State<OfflineSettingsBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    if (localSettings.isLocalGallerySettingsBannerDismissed) {
      return const SizedBox.shrink();
    }

    final textTheme = getEnteTextTheme(context);
    final l10n = context.strings;
    final titleStyle = TextStyles.display3.copyWith(color: Colors.white);

    return GestureDetector(
      onTap: widget.onGetStarted,
      child: Container(
        constraints: const BoxConstraints(minHeight: 190),
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            colors: [
              Color.fromRGBO(21, 21, 21, 1),
              Color.fromRGBO(43, 43, 43, 1),
            ],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _DotsPainter())),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          l10n.offlineSettingsBannerTitle,
                          style: titleStyle,
                        ),
                      ),
                      GestureDetector(
                        onTap: _onDismiss,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: contentLight,
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: HugeIcon(
                              icon: HugeIcons.strokeRoundedCancel01,
                              color: contentDark,
                              size: 18,
                              strokeWidth: 2.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 235),
                    child: Text(
                      l10n.offlineSettingsBannerDesc,
                      style: textTheme.smallMuted.copyWith(
                        color: Colors.white.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  BannerActionButton(
                    label: l10n.getStarted,
                    onTap: widget.onGetStarted,
                    variant: BannerActionButtonVariant.primary,
                    stickTagToLightTheme: true,
                    showTag: true,
                  ),
                ],
              ),
            ),
            Positioned(
              right: 16,
              bottom: 0,
              child: IgnorePointer(
                child: Image.asset(
                  "assets/ducky_settings.png",
                  height: 110,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _onDismiss() {
    setState(() {
      _dismissed = true;
    });
    unawaited(localSettings.setLocalGallerySettingsBannerDismissed(true));
  }
}

class _DotsPainter extends CustomPainter {
  static const double _dotRadius = 2.0;
  static const double _horizontalSpacing = 24.0;
  static const double _verticalSpacing = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..style = PaintingStyle.fill;

    final horizontalCount = (size.width / _horizontalSpacing).ceil() + 1;
    final verticalCount = (size.height / _verticalSpacing).ceil() + 1;

    for (int row = 0; row < verticalCount; row++) {
      for (int col = 0; col < horizontalCount; col++) {
        final x = col * _horizontalSpacing + (_horizontalSpacing / 2);
        final y = row * _verticalSpacing + (_verticalSpacing / 2);

        if (x <= size.width + _dotRadius && y <= size.height + _dotRadius) {
          canvas.drawCircle(Offset(x, y), _dotRadius, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
