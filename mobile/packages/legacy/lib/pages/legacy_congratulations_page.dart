import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:rive/rive.dart" as rive;

class LegacyCongratulationsPage extends StatefulWidget {
  const LegacyCongratulationsPage({super.key});

  @override
  State<LegacyCongratulationsPage> createState() =>
      _LegacyCongratulationsPageState();
}

class _LegacyCongratulationsPageState extends State<LegacyCongratulationsPage> {
  static const _illustrationWidth = 210.0;
  static const _illustrationHeight = 202.0;

  late final rive.FileLoader _animationLoader;

  @override
  void initState() {
    super.initState();
    _animationLoader = rive.FileLoader.fromAsset(
      "packages/ente_legacy/assets/legacy_congratulations.riv",
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: PopScope(
        canPop: false,
        child: Scaffold(
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [colors.primary, const Color(0xFF0A4499)],
              ),
            ),
            child: SafeArea(
              child: Column(
                children: [
                  const Spacer(flex: 2),
                  SizedBox(
                    width: _illustrationWidth,
                    height: _illustrationHeight,
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
                  const SizedBox(height: 36),
                  Text(
                    context.strings.congratulations,
                    textAlign: TextAlign.center,
                    style: TextStyles.display1.copyWith(
                      color: colors.specialWhite,
                    ),
                  ),
                  const SizedBox(height: Spacing.lg),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 42),
                    child: Text(
                      context.strings.legacyCongratulationsMessage,
                      textAlign: TextAlign.center,
                      style: TextStyles.body.copyWith(
                        color: colors.specialWhite,
                      ),
                    ),
                  ),
                  const Spacer(flex: 3),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Spacing.xxl,
                      0,
                      Spacing.xxl,
                      Spacing.xxl,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: Material(
                        color: colors.specialWhite,
                        borderRadius: Radii.buttonBorder,
                        child: InkWell(
                          borderRadius: Radii.buttonBorder,
                          onTap: () => Navigator.of(
                            context,
                          ).popUntil((route) => route.isFirst),
                          child: Center(
                            child: Text(
                              context.strings.saveToLocker,
                              style: TextStyles.body.copyWith(
                                color: const Color(0xFF101010),
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
        ),
      ),
    );
  }
}
