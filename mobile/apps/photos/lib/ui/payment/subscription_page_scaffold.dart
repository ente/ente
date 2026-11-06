import "dart:math" as math;

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/subscription/plan_card.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/ui/account/onboarding_page_scaffold.dart";
import "package:photos/ui/payment/subscription_locker_sheet.dart";

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
  final _noteKey = GlobalKey();
  late double _actionsHeight = _minimumActionHeight * widget.actions.length;
  double _noteHeight = 20;
  bool _measurementScheduled = false;

  void _measureFooter() {
    if (_measurementScheduled) return;
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted) return;
      final height = _actionsKey.currentContext?.size?.height;
      final noteHeight = _noteKey.currentContext?.size?.height;
      final actionsChanged =
          height != null && (height - _actionsHeight).abs() > 0.1;
      final noteChanged =
          noteHeight != null && (noteHeight - _noteHeight).abs() > 0.1;
      if (actionsChanged || noteChanged) {
        setState(() {
          if (actionsChanged) _actionsHeight = height;
          if (noteChanged) _noteHeight = noteHeight;
        });
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
    _measureFooter();
    final colors = context.componentColors;
    final mediaQuery = MediaQuery.of(context);
    final notePadding = math.max(0, kMinInteractiveDimension - _noteHeight);
    final safeBottomInset = math.max(Spacing.xxl, mediaQuery.padding.bottom);
    final noteBottomInset = math.max(0.0, safeBottomInset - notePadding);
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
    final note = SizeChangedLayoutNotifier(child: _buildLockerNote());
    final footer = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        actions,
        if (widget.actions.isNotEmpty) const SizedBox(height: 10),
        note,
      ],
    );
    final footerHeight =
        _fadeHeight +
        _actionsHeight +
        (widget.actions.isEmpty ? 0 : 10) +
        math.max(kMinInteractiveDimension, _noteHeight) +
        noteBottomInset;
    final actionsFooterHeight = _fadeHeight + _actionsHeight + safeBottomInset;
    final availableHeight =
        constraints.maxHeight -
        mediaQuery.padding.top -
        mediaQuery.viewInsets.bottom -
        _headerHeight;
    final hasFloatingFooter =
        availableHeight - footerHeight >= _minimumPlanViewportHeight;
    final hasFloatingActions =
        !hasFloatingFooter &&
        widget.actions.isNotEmpty &&
        availableHeight - actionsFooterHeight >= _minimumPlanViewportHeight;
    final hasPinnedFooter = hasFloatingFooter || hasFloatingActions;
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _measureFooter();
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
            actions: hasPinnedFooter ? const [] : [footer],
            body: Padding(
              padding: EdgeInsets.fromLTRB(
                Spacing.sm,
                0,
                Spacing.sm,
                hasPinnedFooter
                    ? hasFloatingFooter
                          ? footerHeight
                          : actionsFooterHeight
                    : Spacing.xxl,
              ),
              child: hasFloatingActions
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        widget.body,
                        Padding(
                          padding: const EdgeInsets.only(top: Spacing.lg),
                          child: note,
                        ),
                      ],
                    )
                  : widget.body,
            ),
          ),
          if (hasPinnedFooter)
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
                      hasFloatingFooter ? noteBottomInset : safeBottomInset,
                    ),
                    child: hasFloatingFooter ? footer : actions,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLockerNote() {
    final colors = context.componentColors;
    final label = context.strings
        .subscriptionPaidPlansLockerNote(count: 1000, appName: "\uFFFC")
        .split("\uFFFC");
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showSubscriptionLockerSheet(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: kMinInteractiveDimension,
          ),
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: 1,
            child: Row(
              key: _noteKey,
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: HugeIcon(
                    icon: HugeIcons.strokeRoundedInformationCircle,
                    size: 20,
                    color: colors.textLight,
                  ),
                ),
                const SizedBox(width: Spacing.xs),
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: label[0]),
                        TextSpan(
                          text: "Locker",
                          style: TextStyle(
                            decoration: TextDecoration.underline,
                            decorationStyle: TextDecorationStyle.dotted,
                            decorationColor: colors.textLight,
                          ),
                        ),
                        TextSpan(text: label[1]),
                      ],
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyles.mini.copyWith(
                      color: colors.textLight,
                      height: 18 / 12,
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
