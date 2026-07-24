import 'dart:ui';

import 'package:ente_auth/events/codes_updated_event.dart';
import 'package:ente_auth/l10n/l10n.dart';
import 'package:ente_auth/services/preference_service.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_events/event_bus.dart';
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';

class CoachMarkWidget extends StatelessWidget {
  const CoachMarkWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = context.componentColors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _dismiss,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: ColoredBox(
          color: colors.specialScrim,
          child: SafeArea(
            minimum: const EdgeInsets.all(Spacing.lg),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Semantics(
                container: true,
                identifier: 'auth_code_coach_mark',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 520),
                    padding: const EdgeInsets.all(Spacing.xl),
                    decoration: BoxDecoration(
                      color: colors.backgroundBase,
                      borderRadius: BorderRadius.circular(Radii.sheet),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: colors.primaryLight,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.touch_app_outlined,
                            size: IconSizes.medium,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(height: Spacing.lg),
                        Text(
                          PlatformDetector.isDesktop()
                              ? l10n.hintForDesktop
                              : l10n.hintForMobile,
                          textAlign: TextAlign.center,
                          style: TextStyles.bodyBold.copyWith(
                            color: colors.textBase,
                          ),
                        ),
                        const SizedBox(height: Spacing.xl),
                        Semantics(
                          button: true,
                          identifier: 'auth_code_coach_mark_dismiss',
                          child: ButtonComponent(
                            label: l10n.ok,
                            onTap: _dismiss,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _dismiss() async {
    await PreferenceService.instance.setHasShownCoachMark(true);
    Bus.instance.fire(CodesUpdatedEvent());
  }
}
