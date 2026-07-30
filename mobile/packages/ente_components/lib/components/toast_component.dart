import 'package:ente_components/components/banner_component.dart';
import 'package:ente_components/theme/motion.dart';
import 'package:ente_components/theme/spacing.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

/// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=7255-38447&m=dev
/// Section: Snack bar states
/// Specs: bottom-anchored toast built on [BannerComponent] (failure /
/// informative / success / warning / neutral), slide-up + fade, auto-dismiss,
/// tap to dismiss.
///
/// Backed by [FToast], so a new toast replaces any currently-visible one
/// (latest wins, no overlap) and it survives route changes. Only [message] is
/// required; [state] sets the accent + default leading icon (defaults to
/// neutral), [subtitle] adds a second line, [leadingWidget] / [trailingWidget]
/// override the default leading icon / close affordance (trailing shows nothing
/// when omitted), and [duration] sets how long it stays.
void showToastComponent(
  BuildContext context,
  String message, {
  BannerComponentState state = BannerComponentState.neutral,
  String? subtitle,
  Widget? leadingWidget,
  Widget? trailingWidget,
  Duration duration = const Duration(seconds: 4),
}) {
  final fToast = FToast();
  fToast.init(context);
  fToast.removeQueuedCustomToasts();
  fToast.showToast(
    toastDuration: duration,
    fadeDuration: Motion.standard,
    positionedToastBuilder: (context, child, _) {
      final viewPadding = MediaQuery.viewPaddingOf(context);
      return Positioned(
        left: Spacing.lg,
        right: Spacing.lg,
        bottom: viewPadding.bottom + Spacing.xl,
        child: child,
      );
    },
    child: _BannerToast(
      message: message,
      subtitle: subtitle,
      state: state,
      leadingWidget: leadingWidget,
      trailingWidget: trailingWidget,
      onDismiss: fToast.removeCustomToast,
    ),
  );
}

class _BannerToast extends StatelessWidget {
  const _BannerToast({
    required this.message,
    required this.subtitle,
    required this.state,
    required this.leadingWidget,
    required this.trailingWidget,
    required this.onDismiss,
  });

  final String message;
  final String? subtitle;
  final BannerComponentState state;
  final Widget? leadingWidget;
  final Widget? trailingWidget;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1 - value) * 24),
            child: child,
          ),
        );
      },
      child: Material(
        type: MaterialType.transparency,
        child: BannerComponent(
          title: message,
          subtitle: subtitle,
          state: state,
          leadingWidget: leadingWidget,
          trailingWidget: trailingWidget ?? const SizedBox.shrink(),
          onTap: onDismiss,
        ),
      ),
    );
  }
}
