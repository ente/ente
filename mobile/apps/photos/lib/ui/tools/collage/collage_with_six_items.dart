import "package:flutter/material.dart";
import "package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/tools/collage/collage_common_widgets.dart";
import "package:photos/ui/tools/collage/collage_item_icon.dart";
import "package:photos/ui/tools/collage/collage_item_widget.dart";
import "package:photos/ui/tools/collage/collage_swap_mixin.dart";
import "package:widgets_to_image/widgets_to_image.dart";

enum Variant { first, second }

class CollageWithSixItems extends StatefulWidget {
  const CollageWithSixItems(
    this.first,
    this.second,
    this.third,
    this.fourth,
    this.fifth,
    this.sixth, {
    super.key,
    this.onControllerReady,
    this.onSelectionClearSetter,
  });

  final EnteFile first, second, third, fourth, fifth, sixth;
  final ValueChanged<WidgetsToImageController>? onControllerReady;
  final ValueChanged<VoidCallback>? onSelectionClearSetter;

  @override
  State<CollageWithSixItems> createState() => _CollageWithSixItemsState();
}

class _CollageWithSixItemsState extends State<CollageWithSixItems>
    with CollageSwapMixin<CollageWithSixItems> {
  final _widgetsToImageController = WidgetsToImageController();
  Variant _variant = Variant.first;

  @override
  void initState() {
    super.initState();
    initCollageFiles([
      widget.first,
      widget.second,
      widget.third,
      widget.fourth,
      widget.fifth,
      widget.sixth,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onControllerReady?.call(_widgetsToImageController);
      widget.onSelectionClearSetter?.call(clearSwapSelection);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    WidgetsToImage(
                      controller: _widgetsToImageController,
                      child: _getCollage(),
                    ),
                    Column(
                      children: [
                        const CollageLayoutHeading(),
                        _getLayouts(),
                        const Padding(padding: EdgeInsets.all(4)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _getLayouts() {
    return Row(
      children: [
        CollageLayoutIconButton(
          child: FirstVariantIcon(isActive: _variant == Variant.first),
          onTap: () {
            setState(() {
              _variant = Variant.first;
            });
          },
        ),
        const Padding(padding: EdgeInsets.all(2)),
        CollageLayoutIconButton(
          child: SecondVariantIcon(isActive: _variant == Variant.second),
          onTap: () {
            setState(() {
              _variant = Variant.second;
            });
          },
        ),
      ],
    );
  }

  Widget _getCollage() {
    switch (_variant) {
      case Variant.first:
        return FirstVariant(
          _collageItem(0),
          _collageItem(1),
          _collageItem(2),
          _collageItem(3),
          _collageItem(4),
          _collageItem(5),
        );
      case Variant.second:
        return SizedBox(
          width: 320,
          child: SecondVariant(
            _collageItem(0),
            _collageItem(1),
            _collageItem(2),
            _collageItem(3),
            _collageItem(4),
            _collageItem(5),
          ),
        );
    }
  }

  CollageItemWidget _collageItem(int index) {
    return CollageItemWidget(
      collageFiles[index],
      onTap: () => onCollageItemTapped(index),
      onLongPress: () => onCollageItemLongPressed(index),
      isSelected: isSelectedForSwap(index),
      isSwapActive: isSwapSelectionActive,
    );
  }
}

class FirstVariant extends StatelessWidget {
  const FirstVariant(
    this.first,
    this.second,
    this.third,
    this.fourth,
    this.fifth,
    this.sixth, {
    super.key,
    this.mainAxisSpacing = 4,
    this.crossAxisSpacing = 4,
    this.color = Colors.white,
  });

  final Widget first, second, third, fourth, fifth, sixth;
  final double mainAxisSpacing, crossAxisSpacing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: StaggeredGrid.count(
          crossAxisCount: 3,
          mainAxisSpacing: mainAxisSpacing,
          crossAxisSpacing: crossAxisSpacing,
          axisDirection: AxisDirection.down,
          children: [
            StaggeredGridTile.count(
              crossAxisCellCount: 2,
              mainAxisCellCount: 2,
              child: first,
            ),
            StaggeredGridTile.count(
              crossAxisCellCount: 1,
              mainAxisCellCount: 1,
              child: second,
            ),
            StaggeredGridTile.count(
              crossAxisCellCount: 1,
              mainAxisCellCount: 1,
              child: third,
            ),
            StaggeredGridTile.count(
              crossAxisCellCount: 1,
              mainAxisCellCount: 1,
              child: fourth,
            ),
            StaggeredGridTile.count(
              crossAxisCellCount: 1,
              mainAxisCellCount: 1,
              child: fifth,
            ),
            StaggeredGridTile.count(
              crossAxisCellCount: 1,
              mainAxisCellCount: 1,
              child: sixth,
            ),
          ],
        ),
      ),
    );
  }
}

class SecondVariant extends StatelessWidget {
  const SecondVariant(
    this.first,
    this.second,
    this.third,
    this.fourth,
    this.fifth,
    this.sixth, {
    super.key,
    this.mainAxisSpacing = 4,
    this.crossAxisSpacing = 4,
    this.color = Colors.white,
  });

  final Widget first, second, third, fourth, fifth, sixth;
  final double mainAxisSpacing, crossAxisSpacing;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: StaggeredGrid.count(
          crossAxisCount: 2,
          mainAxisSpacing: mainAxisSpacing,
          crossAxisSpacing: crossAxisSpacing,
          axisDirection: AxisDirection.down,
          children: [
            StaggeredGridTile.count(
              crossAxisCellCount: 1,
              mainAxisCellCount: 1,
              child: first,
            ),
            StaggeredGridTile.count(
              crossAxisCellCount: 1,
              mainAxisCellCount: 1,
              child: second,
            ),
            StaggeredGridTile.count(
              crossAxisCellCount: 1,
              mainAxisCellCount: 1,
              child: third,
            ),
            StaggeredGridTile.count(
              crossAxisCellCount: 1,
              mainAxisCellCount: 1,
              child: fourth,
            ),
            StaggeredGridTile.count(
              crossAxisCellCount: 1,
              mainAxisCellCount: 1,
              child: fifth,
            ),
            StaggeredGridTile.count(
              crossAxisCellCount: 1,
              mainAxisCellCount: 1,
              child: sixth,
            ),
          ],
        ),
      ),
    );
  }
}

class FirstVariantIcon extends StatelessWidget {
  const FirstVariantIcon({super.key, this.isActive = false});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return CollageIconContainerWidget(
      width: 56,
      child: FirstVariant(
        CollageItemIcon(isActive: isActive),
        CollageItemIcon(isActive: isActive),
        CollageItemIcon(isActive: isActive),
        CollageItemIcon(isActive: isActive),
        CollageItemIcon(isActive: isActive),
        CollageItemIcon(isActive: isActive),
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        color: Colors.transparent,
      ),
    );
  }
}

class SecondVariantIcon extends StatelessWidget {
  const SecondVariantIcon({super.key, this.isActive = false});
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return CollageIconContainerWidget(
      child: SecondVariant(
        CollageItemIcon(isActive: isActive),
        CollageItemIcon(isActive: isActive),
        CollageItemIcon(isActive: isActive),
        CollageItemIcon(isActive: isActive),
        CollageItemIcon(isActive: isActive),
        CollageItemIcon(isActive: isActive),
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        color: Colors.transparent,
      ),
    );
  }
}
