import "package:ente_accounts/models/user_details.dart";
import 'package:ente_components/ente_components.dart';
import "package:ente_ui/components/loading_widget.dart";
import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:locker/l10n/l10n.dart";
import "package:locker/services/configuration.dart";
import "package:locker/states/user_details_state.dart";

class UsageCardWidget extends StatelessWidget {
  const UsageCardWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final inheritedDetails = InheritedUserDetails.of(context);
    final userDetails = inheritedDetails?.userDetails;
    final isCached = inheritedDetails?.isCached ?? false;
    final isLoading = userDetails is! UserDetails || isCached;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [
              Color.fromRGBO(21, 21, 21, 1),
              Color.fromRGBO(43, 43, 43, 1),
            ],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _DotsPainter(colors.specialWhite),
                size: Size.infinite,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: _UsageContent(
                userDetails: userDetails,
                isLoading: isLoading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  final Color dotColor;

  const _DotsPainter(this.dotColor);

  static const double _dotRadius = 2.0;
  static const double _horizontalSpacing = 24.0;
  static const double _verticalSpacing = 24.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = dotColor.withValues(alpha: 0.03)
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

class _UsageContent extends StatelessWidget {
  final UserDetails? userDetails;
  final bool isLoading;

  const _UsageContent({required this.userDetails, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    final cardText = colors.specialWhite;
    final cardTextMuted = cardText.withValues(alpha: 0.7);
    final maxFileCount = _effectiveLockerFileLimit(
      userDetails,
    ).clamp(1, double.maxFinite).toInt();
    final userFileCount = userDetails?.fileCount ?? 0;

    final showFamilyBreakup = _shouldShowFamilyBreakup();

    final userProgress = isLoading
        ? 0.0
        : (userFileCount / maxFileCount).clamp(0.0, 1.0);
    final familyProgress = showFamilyBreakup && !isLoading
        ? (userDetails!.lockerFamilyUsage!.familyFileCount / maxFileCount)
              .clamp(0.0, 1.0)
        : 0.0;

    final formattedUsed = NumberFormat().format(userFileCount);
    final formattedMax = NumberFormat().format(maxFileCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          context.l10n.itemsStored,
          style: TextStyles.large.copyWith(color: cardTextMuted),
        ),
        const SizedBox(height: 4),
        if (isLoading)
          SizedBox(
            height: 40,
            child: Align(
              alignment: Alignment.centerLeft,
              child: EnteLoadingWidget(size: 24, padding: 0, color: cardText),
            ),
          )
        else
          RichText(
            text: TextSpan(
              style: TextStyles.h1.copyWith(color: cardText),
              children: [
                TextSpan(text: formattedUsed),
                TextSpan(
                  text: " ${context.l10n.of_} ",
                  style: TextStyles.h1.copyWith(color: cardTextMuted),
                ),
                TextSpan(text: formattedMax),
              ],
            ),
          ),
        const SizedBox(height: 16),
        SizedBox(
          height: 8,
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                height: 8,
                decoration: BoxDecoration(
                  color: colors.specialWhiteOverlay,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              if (showFamilyBreakup)
                LayoutBuilder(
                  builder: (context, constraints) {
                    return Container(
                      width: constraints.maxWidth * familyProgress,
                      height: 8,
                      decoration: BoxDecoration(
                        color: cardText,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  },
                ),
              LayoutBuilder(
                builder: (context, constraints) {
                  return Container(
                    width: constraints.maxWidth * userProgress,
                    height: 8,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (showFamilyBreakup && !isLoading)
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                context.l10n.usageYou,
                style: TextStyles.mini.copyWith(color: cardText),
              ),
              const SizedBox(width: 16),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cardText,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                context.l10n.usageFamily,
                style: TextStyles.mini.copyWith(color: cardText),
              ),
            ],
          )
        else
          const SizedBox(height: 4),
      ],
    );
  }

  bool _shouldShowFamilyBreakup() {
    if (userDetails == null) return false;
    if (!userDetails!.isPartOfFamily()) return false;
    return userDetails!.lockerFamilyUsage != null;
  }

  int _effectiveLockerFileLimit(UserDetails? userDetails) {
    final currentLimit = userDetails?.getLockerFileLimit() ?? 100;
    if (!Configuration.instance.isEnteProduction() && currentLimit < 1000) {
      return 1000;
    }
    return currentLimit;
  }
}
