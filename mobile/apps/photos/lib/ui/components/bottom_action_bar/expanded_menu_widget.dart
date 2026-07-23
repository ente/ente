import 'package:flutter/material.dart';
import 'package:photos/ui/components/blur_menu_item_widget.dart';
import 'package:photos/ui/components/divider_widget.dart';

class ExpandedMenuWidget extends StatelessWidget {
  final List<List<BlurMenuItemWidget>> items;
  const ExpandedMenuWidget({required this.items, super.key});

  @override
  Widget build(BuildContext context) {
    final textScaler = MediaQuery.of(context).textScaler;
    //20 is height of font and 28 is total whitespace (top+bottom)
    var scaledHeight = textScaler.scale(20);
    if (scaledHeight < 20) {
      scaledHeight = 20;
    }
    final double itemHeight = scaledHeight + 28.0;
    const double whiteSpaceBetweenSections = 16.0;
    const double dividerHeightBetweenItems = 1.0;
    double numberOfDividers = 0.0;
    double combinedHeightOfItems = 0.0;

    for (List<BlurMenuItemWidget> group in items) {
      //no divider if there is only one item in the section/group
      if (group.length != 1) {
        numberOfDividers += (group.length - 1);
      }
      combinedHeightOfItems += group.length * itemHeight;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: SizedBox(
        height:
            combinedHeightOfItems +
            (dividerHeightBetweenItems * numberOfDividers) +
            (whiteSpaceBetweenSections * (items.length - 1.0)),
        child: ListView.separated(
          padding: const EdgeInsets.all(0),
          physics: const NeverScrollableScrollPhysics(),
          itemBuilder: (context, sectionIndex) {
            return ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(8)),
              child: SizedBox(
                height:
                    itemHeight * items[sectionIndex].length +
                    (dividerHeightBetweenItems *
                        (items[sectionIndex].length - 1)),
                child: ListView.separated(
                  padding: const EdgeInsets.all(0),
                  physics: const NeverScrollableScrollPhysics(),
                  itemBuilder: (context, itemIndex) {
                    return items[sectionIndex][itemIndex];
                  },
                  separatorBuilder: (context, index) {
                    return const DividerWidget(
                      dividerType: DividerType.bottomBar,
                    );
                  },
                  itemCount: items[sectionIndex].length,
                ),
              ),
            );
          },
          separatorBuilder: (context, index) {
            return const SizedBox(height: whiteSpaceBetweenSections);
          },
          itemCount: items.length,
        ),
      ),
    );
  }
}
