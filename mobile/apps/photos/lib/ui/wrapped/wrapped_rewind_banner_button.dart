import "package:flutter/material.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/wrapped/models.dart";
import "package:photos/services/wrapped/wrapped_service.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/ui/wrapped/wrapped_viewer_page.dart";
import "package:rive/rive.dart" as rive;

class WrappedRewindBannerButton extends StatefulWidget {
  const WrappedRewindBannerButton({
    super.key,
    this.height,
    this.semanticsLabel,
  });

  final double? height;
  final String? semanticsLabel;

  @override
  State<WrappedRewindBannerButton> createState() =>
      _WrappedRewindBannerButtonState();
}

class _WrappedRewindBannerButtonState extends State<WrappedRewindBannerButton> {
  late final rive.FileLoader _riveFileLoader;
  double? _artboardAspectRatio;

  @override
  void initState() {
    super.initState();
    _riveFileLoader = rive.FileLoader.fromAsset(
      "assets/ente_rewind_banner.riv",
      riveFactory: rive.Factory.flutter,
    );
  }

  @override
  void dispose() {
    _riveFileLoader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = getEnteTextTheme(context);
    const BorderRadius borderRadius = BorderRadius.all(Radius.circular(24));

    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: () => _handleTap(context),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double availableWidth =
                  constraints.hasBoundedWidth && constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : MediaQuery.sizeOf(context).width;
              double? resolvedHeight = widget.height;
              if (resolvedHeight == null &&
                  _artboardAspectRatio != null &&
                  _artboardAspectRatio! > 0 &&
                  availableWidth.isFinite) {
                resolvedHeight = availableWidth / _artboardAspectRatio!;
              }
              resolvedHeight ??= 128;

              return ClipRRect(
                borderRadius: borderRadius,
                child: SizedBox(
                  height: resolvedHeight,
                  width: double.infinity,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: rive.RiveWidgetBuilder(
                          fileLoader: _riveFileLoader,
                          stateMachineSelector: const rive.StateMachineNamed(
                            "State Machine 1",
                          ),
                          onLoaded: _handleRiveLoaded,
                          builder:
                              (BuildContext context, rive.RiveState state) {
                                if (state is rive.RiveLoaded) {
                                  return rive.RiveWidget(
                                    controller: state.controller,
                                    fit: rive.Fit.cover,
                                  );
                                }
                                if (state is rive.RiveFailed) {
                                  return const ColoredBox(color: Colors.black);
                                }
                                return const SizedBox.expand();
                              },
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                "Ente Rewind 2025",
                                style: textTheme.h3Bold.copyWith(
                                  fontSize:
                                      (textTheme.h3Bold.fontSize ?? 24) + 2,
                                  color: Colors.white,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              width: 28,
                              height: 28,
                              decoration: const BoxDecoration(
                                color: Color(0x99000000),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  void _handleRiveLoaded(rive.RiveLoaded loaded) {
    if (!mounted) return;
    final rive.AABB bounds = loaded.controller.artboard.bounds;
    final double height = bounds.height;
    final double width = bounds.width;
    if (height <= 0 || width <= 0) {
      return;
    }
    final double aspectRatio = width / height;
    if (aspectRatio == _artboardAspectRatio) {
      return;
    }
    setState(() {
      _artboardAspectRatio = aspectRatio;
    });
  }

  void _handleTap(BuildContext context) {
    final WrappedEntryState currentState = wrappedService.state;
    final WrappedResult? result = currentState.result;
    if (result == null || result.cards.isEmpty) {
      showShortToast(context, "Ente Rewind isn't ready yet");
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            WrappedViewerPage(initialState: currentState),
      ),
    );
  }
}
