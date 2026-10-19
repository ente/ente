import 'dart:async';

import 'package:ente_components/components/loading/loading_component.dart';
import 'package:ente_components/theme/motion.dart';
import 'package:ente_components/theme/radii.dart';
import 'package:ente_components/theme/shadows.dart';
import 'package:ente_components/theme/spacing.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';

LoadingComponentHandle showLoadingComponent(
  BuildContext context,
  String message, {
  bool isDismissible = false,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  final updates = ValueNotifier(message);
  final route = RawDialogRoute<void>(
    barrierDismissible: isDismissible,
    barrierColor: context.componentColors.specialScrim,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: Motion.standard,
    transitionBuilder: _loadingTransition,
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    pageBuilder: (_, _, _) => themes.wrap(
      PopScope(
        canPop: isDismissible,
        child: SafeArea(child: _LoadingDialog(message: updates)),
      ),
    ),
  );
  unawaited(route.completed.then((_) => updates.dispose()));
  unawaited(navigator.push(route));
  return LoadingComponentHandle._(route, updates);
}

class LoadingComponentHandle {
  LoadingComponentHandle._(this._route, this._message);

  final RawDialogRoute<void> _route;
  final ValueNotifier<String> _message;

  bool isShowing() => _route.isActive;

  void update({String? message}) {
    if (!_route.isActive) return;
    if (message != null) _message.value = message;
  }

  Future<void> hide() {
    final navigator = _route.navigator;
    if (navigator != null && _route.isActive) {
      if (_route.isCurrent) {
        navigator.pop();
      } else {
        navigator.removeRoute(_route);
      }
    }
    return _route.completed;
  }
}

class _LoadingDialog extends StatelessWidget {
  const _LoadingDialog({required this.message});

  final ValueNotifier<String> message;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: Spacing.xl),
      child: ValueListenableBuilder<String>(
        valueListenable: message,
        builder: (_, message, _) => Container(
          width: 288,
          padding: const EdgeInsets.symmetric(
            horizontal: Spacing.xxl,
            vertical: Spacing.xl,
          ),
          decoration: BoxDecoration(
            color: colors.backgroundBase,
            border: Border.all(color: colors.strokeFaint),
            borderRadius: Radii.buttonBorder,
            boxShadow: Shadows.floating,
          ),
          child: Row(
            children: [
              const LoadingComponent(),
              const SizedBox(width: Spacing.lg),
              Expanded(
                child: Text(
                  message,
                  style: TextStyles.body.copyWith(color: colors.textBase),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _loadingTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  return FadeTransition(
    opacity: animation,
    child: ScaleTransition(
      scale: animation.drive(
        Tween<double>(
          begin: 0.96,
          end: 1,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
      ),
      child: child,
    ),
  );
}
