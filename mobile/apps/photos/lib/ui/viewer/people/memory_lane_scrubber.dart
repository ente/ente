import "package:flutter/material.dart";

class MemoryLaneScrubber extends StatelessWidget {
  const MemoryLaneScrubber({
    required this.totalEntries,
    required this.currentIndex,
    required this.onTap,
    required this.onSeek,
    required this.onSeekEnd,
    super.key,
  }) : assert(totalEntries > 0);

  final int totalEntries;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final ValueChanged<int> onSeek;
  final VoidCallback onSeekEnd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontalPadding = MediaQuery.sizeOf(context).width * 0.16;
        final trackWidth = constraints.maxWidth - horizontalPadding * 2;
        if (trackWidth <= 0) return const SizedBox(height: 40);

        const maxDotSize = 15.0;
        const dotSpacing = 5.0;
        final dotCount = ((trackWidth + dotSpacing) / (maxDotSize + dotSpacing))
            .floor()
            .clamp(1, totalEntries);
        final activeDot = currentIndex * dotCount ~/ totalEntries;

        int indexAt(double x) =>
            ((x - horizontalPadding) / trackWidth * totalEntries).floor().clamp(
              0,
              totalEntries - 1,
            );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) => onTap(indexAt(details.localPosition.dx)),
          onHorizontalDragStart: (details) =>
              onSeek(indexAt(details.localPosition.dx)),
          onHorizontalDragUpdate: (details) =>
              onSeek(indexAt(details.localPosition.dx)),
          onHorizontalDragEnd: (_) => onSeekEnd(),
          onHorizontalDragCancel: onSeekEnd,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            child: Row(
              spacing: dotSpacing,
              children: List.generate(dotCount, (index) {
                final distance = (index - activeDot).abs();
                final double size = switch (distance) {
                  0 => maxDotSize,
                  1 => 10,
                  2 => 7.5,
                  _ => 5,
                };
                return Expanded(
                  child: SizedBox(
                    height: 40,
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: size,
                        height: size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(
                            alpha: distance == 0 ? 1 : 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}
