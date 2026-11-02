import "dart:math" as math;

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/subscription/plan_card.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/ui/account/onboarding_page_scaffold.dart";

class SubscriptionPageScaffold extends StatefulWidget {
  const SubscriptionPageScaffold({
    super.key,
    this.scaffoldKey,
    required this.body,
    required this.onHelpTap,
    this.actions = const [],
    this.isBodyCentered = false,
  });

  final GlobalKey<OnboardingPageScaffoldState>? scaffoldKey;
  final Widget body;
  final VoidCallback onHelpTap;
  final List<Widget> actions;
  final bool isBodyCentered;

  @override
  State<SubscriptionPageScaffold> createState() =>
      _SubscriptionPageScaffoldState();
}

class _SubscriptionPageScaffoldState extends State<SubscriptionPageScaffold> {
  static const double _headerHeight = 145;
  static const double _fadeHeight = 80;
  static const double _minimumActionHeight = 60;
  static const double _minimumPlanViewportHeight =
      SubscriptionPlanCard.height + Spacing.xxl * 2;

  final _actionsKey = GlobalKey();
  double _actionsHeight = _minimumActionHeight;
  bool _measurementScheduled = false;

  void _measureActions() {
    if (_measurementScheduled) return;
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted) return;
      final height = _actionsKey.currentContext?.size?.height;
      if (height != null && (height - _actionsHeight).abs() > 0.1) {
        setState(() => _actionsHeight = height);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => _buildLayout(context, constraints),
    );
  }

  Widget _buildLayout(BuildContext context, BoxConstraints constraints) {
    _measureActions();
    final colors = context.componentColors;
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = math.max(Spacing.xxl, mediaQuery.padding.bottom);
    final footerHeight = _fadeHeight + _actionsHeight + bottomInset;
    final actions = SizeChangedLayoutNotifier(
      child: Column(
        key: _actionsKey,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final action in widget.actions)
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: _minimumActionHeight,
              ),
              child: action,
            ),
        ],
      ),
    );
    final hasFloatingActions =
        widget.actions.isNotEmpty &&
        constraints.maxHeight -
                mediaQuery.padding.top -
                mediaQuery.viewInsets.bottom -
                _headerHeight -
                footerHeight >=
            _minimumPlanViewportHeight;
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _measureActions();
        return false;
      },
      child: Stack(
        children: [
          OnboardingPageScaffold(
            key: widget.scaffoldKey,
            title: context.strings.chooseYourPlan,
            illustration: OnboardingIllustration.pricing,
            headerHeight: _headerHeight,
            titleTopPadding: 35,
            bodyHorizontalPadding: Spacing.lg - 1,
            titleBarStyle: OnboardingTitleBarStyle.header,
            headerTrailing: IconButtonComponent(
              variant: IconButtonComponentVariant.unfilled,
              size: 48,
              iconSize: IconSizes.medium,
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedHelpCircle,
                color: colors.specialWhite,
              ),
              tooltip: context.strings.faqs,
              onTap: widget.onHelpTap,
            ),
            manageInputFocus: false,
            isBodyCentered: widget.isBodyCentered,
            actions: widget.actions.isNotEmpty && !hasFloatingActions
                ? [actions]
                : const [],
            body: Padding(
              padding: EdgeInsets.fromLTRB(
                Spacing.sm,
                0,
                Spacing.sm,
                hasFloatingActions ? footerHeight : Spacing.xxl,
              ),
              child: widget.body,
            ),
          ),
          if (hasFloatingActions)
            Positioned(
              left: 0,
              right: 0,
              bottom: 1,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              colors.backgroundBase.withValues(alpha: 0),
                              colors.backgroundBase,
                            ],
                            stops: const [0, 0.73],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      Spacing.lg + mediaQuery.padding.left,
                      _fadeHeight,
                      Spacing.lg + mediaQuery.padding.right,
                      bottomInset,
                    ),
                    child: actions,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
