import "package:flutter/material.dart";
import "package:photos/services/wrapped/wrapped_service.dart"
    show WrappedEntryState;
import "package:photos/ui/wrapped/wrapped_rewind_banner_button.dart";

class WrappedDiscoverySection extends StatelessWidget {
  const WrappedDiscoverySection({required this.state, super.key});

  final WrappedEntryState state;

  @override
  Widget build(BuildContext context) {
    final bool hasProgress =
        state.resumeIndex > 0 &&
        state.resumeIndex < (state.result?.cards.length ?? 0);
    final String semanticsLabel = hasProgress && !state.isComplete
        ? "Resume Ente Rewind 2025"
        : "Open Ente Rewind 2025";

    const double bleed = 12;
    const double bannerHeight = 164;

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 24),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double baseWidth =
              constraints.hasBoundedWidth && constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width;
          final double targetWidth = baseWidth + bleed * 2;

          return SizedBox(
            height: bannerHeight,
            child: OverflowBox(
              alignment: Alignment.center,
              minWidth: targetWidth,
              maxWidth: targetWidth,
              minHeight: bannerHeight,
              maxHeight: bannerHeight,
              child: SizedBox(
                width: targetWidth,
                height: bannerHeight,
                child: WrappedRewindBannerButton(
                  height: bannerHeight,
                  semanticsLabel: semanticsLabel,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
