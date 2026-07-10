import 'dart:async';

import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import 'package:locker/l10n/l10n.dart';
import 'package:rive/rive.dart' as rive;

class HomeEmptyStateWidget extends StatefulWidget {
  const HomeEmptyStateWidget({
    super.key,
    this.isLoading = false,
    this.onSetupLegacy,
    this.onSaveToLocker,
  });

  final bool isLoading;
  final FutureOr<void> Function()? onSetupLegacy;
  final FutureOr<void> Function()? onSaveToLocker;

  @override
  State<HomeEmptyStateWidget> createState() => _HomeEmptyStateWidgetState();
}

class _HomeEmptyStateWidgetState extends State<HomeEmptyStateWidget> {
  late final rive.FileLoader _animationLoader;

  @override
  void initState() {
    super.initState();
    _animationLoader = rive.FileLoader.fromAsset(
      'assets/legacy_setup.riv',
      riveFactory: rive.Factory.flutter,
    );
  }

  @override
  void dispose() {
    _animationLoader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return widget.isLoading
        ? CircularProgressIndicator(strokeWidth: 3, color: colors.primary)
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 234,
                height: 140,
                child: rive.RiveWidgetBuilder(
                  fileLoader: _animationLoader,
                  builder: (context, state) {
                    if (state is rive.RiveLoaded) {
                      return rive.RiveWidget(
                        controller: state.controller,
                        fit: rive.Fit.contain,
                      );
                    }
                    return const SizedBox.expand();
                  },
                ),
              ),
              const SizedBox(height: 40),
              Text(
                context.l10n.homeEmptyStateLegacyDescription,
                style: TextStyles.body.copyWith(color: colors.textLight),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              Column(
                children: [
                  ButtonComponent(
                    label: context.l10n.setupYourLegacy,
                    onTap: widget.onSetupLegacy,
                  ),
                  const SizedBox(height: 12),
                  ButtonComponent(
                    label: context.l10n.saveToLocker,
                    variant: ButtonComponentVariant.neutral,
                    onTap: widget.onSaveToLocker,
                  ),
                ],
              ),
            ],
          );
  }
}
