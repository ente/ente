import "package:flutter/material.dart";
import "package:rive/rive.dart" as rive;

/// Overlay widget that appears at the top of the screen when pulling down.
/// This shows the Merry Christmas animation with the duck character.
class ChristmasPullOverlay extends StatefulWidget {
  final double pullOffset;
  final bool isReleased;
  final double triggerThreshold;

  const ChristmasPullOverlay({
    super.key,
    required this.pullOffset,
    this.isReleased = false,
    this.triggerThreshold = 60,
  });

  @override
  State<ChristmasPullOverlay> createState() => _ChristmasPullOverlayState();
}

class _ChristmasPullOverlayState extends State<ChristmasPullOverlay> {
  late final rive.FileLoader _riveFileLoader;
  rive.BooleanInput? _triggerInput;

  @override
  void initState() {
    super.initState();
    _riveFileLoader = rive.FileLoader.fromAsset(
      "assets/x_mas.riv",
      riveFactory: rive.Factory.flutter,
    );
  }

  @override
  void dispose() {
    _riveFileLoader.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(ChristmasPullOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Set trigger to true when pulled past threshold
    if (widget.pullOffset >= widget.triggerThreshold) {
      _triggerInput?.value = true;
    }

    // Set trigger to false when released
    if (widget.isReleased) {
      _triggerInput?.value = false;
    }
  }

  void _onRiveLoaded(rive.RiveLoaded loaded) {
    final controller = loaded.controller;
    _triggerInput = controller.stateMachine.boolean("Trigger");
  }

  @override
  Widget build(BuildContext context) {
    final double pullOffset = widget.pullOffset;
    if (pullOffset <= 0) {
      return const SizedBox.shrink();
    }

    // Multiplier to reveal animation faster with less scrolling
    const double multiplier = 35.0;
    final double animationHeight = pullOffset * multiplier;

    return SizedBox(
      height: pullOffset,
      width: double.infinity,
      child: ClipRect(
        child: OverflowBox(
          maxHeight: animationHeight,
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            height: animationHeight,
            width: double.infinity,
            child: rive.RiveWidgetBuilder(
              fileLoader: _riveFileLoader,
              stateMachineSelector: const rive.StateMachineNamed(
                "State Machine 1",
              ),
              onLoaded: _onRiveLoaded,
              builder: (BuildContext context, rive.RiveState state) {
                if (state is rive.RiveLoaded) {
                  return rive.RiveWidget(
                    controller: state.controller,
                    fit: rive.Fit.fitWidth,
                    alignment: Alignment.bottomCenter,
                  );
                }
                if (state is rive.RiveFailed) {
                  return const SizedBox.shrink();
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ),
    );
  }
}
