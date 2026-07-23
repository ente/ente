import 'package:ente_components/ente_components.dart';
import 'package:flutter/material.dart';

/// A thin scrollbar rendered beside a bounded [ListView], with the thumb sized
/// to [visibleItems] of [itemCount] and positioned from the shared
/// [scrollController]. Shared by the add-email and share-collection sheets.
class CustomListScrollbar extends StatelessWidget {
  const CustomListScrollbar({
    super.key,
    required this.scrollController,
    required this.itemCount,
    required this.visibleItems,
    required this.containerHeight,
  });

  final ScrollController scrollController;
  final int itemCount;
  final int visibleItems;
  final double containerHeight;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final thumbHeightRatio = visibleItems / itemCount;
    final thumbHeight = containerHeight * thumbHeightRatio;

    return AnimatedBuilder(
      animation: scrollController,
      builder: (context, child) {
        double thumbPosition = 0;
        if (scrollController.hasClients &&
            scrollController.positions.length == 1) {
          final maxExtent = scrollController.position.hasContentDimensions
              ? scrollController.position.maxScrollExtent
              : 0.0;
          if (maxExtent > 0) {
            final scrollFraction = scrollController.offset / maxExtent;
            thumbPosition = scrollFraction * (containerHeight - thumbHeight);
          }
        }

        return SizedBox(
          height: containerHeight,
          width: 5,
          child: Stack(
            children: [
              Container(
                width: 5,
                height: containerHeight,
                decoration: BoxDecoration(
                  color: colors.strokeFaint,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Positioned(
                top: thumbPosition,
                child: Container(
                  width: 5,
                  height: thumbHeight,
                  decoration: BoxDecoration(
                    color: colors.strokeDark,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
