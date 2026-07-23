import "package:ente_components/ente_components.dart";
import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/material.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

class GlacierFilterMatrix {
  static const saturation = [
    0.97,
    0.02,
    0.00,
    0.00,
    0.00,
    0.01,
    0.98,
    0.00,
    0.00,
    0.00,
    0.01,
    0.02,
    0.96,
    0.00,
    0.00,
    0.00,
    0.00,
    0.00,
    1.00,
    0.00,
  ];

  static const contrast = [
    0.94,
    0.00,
    0.00,
    0.00,
    7.07,
    0.00,
    0.94,
    0.00,
    0.00,
    7.07,
    0.00,
    0.00,
    0.94,
    0.00,
    7.07,
    0.00,
    0.00,
    0.00,
    1.00,
    0.00,
  ];

  static const hue = [
    1.01,
    0.40,
    -0.41,
    0.00,
    0.00,
    -0.04,
    0.91,
    0.14,
    0.00,
    0.00,
    0.38,
    -0.25,
    0.87,
    0.00,
    0.00,
    0.00,
    0.00,
    0.00,
    1.00,
    0.00,
  ];

  static const temperature = [
    0.80,
    0.00,
    0.00,
    0.00,
    0.00,
    0.00,
    1.00,
    0.00,
    0.00,
    0.00,
    0.00,
    0.00,
    1.00,
    0.00,
    0.00,
    0.00,
    0.00,
    0.00,
    1.00,
    0.00,
  ];
}

final filterList = [
  const FilterModel(name: "None", filters: []),
  FilterModel(
    name: 'Pop',
    filters: [
      ColorFilterAddons.saturation(0.3),
      ColorFilterAddons.brightness(0.15),
    ],
  ),
  FilterModel(
    name: "Amber",
    filters: [
      ColorFilterAddons.rgbScale(1.01, 1.04, 1),
      ColorFilterAddons.saturation(0.3),
    ],
  ),
  FilterModel(
    name: 'Dust',
    filters: [
      ColorFilterAddons.sepia(0.4),
      ColorFilterAddons.brightness(0.13),
      ColorFilterAddons.contrast(-.05),
    ],
  ),
  FilterModel(
    name: 'Carbon',
    filters: [ColorFilterAddons.contrast(0.2), ColorFilterAddons.grayscale()],
  ),
  const FilterModel(
    name: 'Glacier',
    filters: [
      GlacierFilterMatrix.saturation,
      GlacierFilterMatrix.temperature,
      GlacierFilterMatrix.hue,
      GlacierFilterMatrix.contrast,
    ],
  ),
  FilterModel(
    name: 'Haze',
    filters: [
      ColorFilterAddons.colorOverlay(228, 130, 225, 0.13),
      ColorFilterAddons.saturation(-0.2),
    ],
  ),
  FilterModel(
    name: 'Meadow',
    filters: [ColorFilterAddons.rgbScale(1.05, 1.1, 1)],
  ),
  FilterModel(
    name: 'Zest',
    filters: [
      ColorFilterAddons.brightness(.1),
      ColorFilterAddons.contrast(.1),
      ColorFilterAddons.saturation(.15),
    ],
  ),
  FilterModel(
    name: 'Retro',
    filters: [
      ColorFilterAddons.colorOverlay(25, 240, 252, 0.05),
      ColorFilterAddons.sepia(0.3),
    ],
  ),
  FilterModel(
    name: 'Sepia',
    filters: [
      ColorFilterAddons.contrast(-0.15),
      ColorFilterAddons.saturation(0.1),
    ],
  ),
];

class ImageEditorFilterBar extends StatefulWidget {
  const ImageEditorFilterBar({
    required this.filterModel,
    required this.isSelected,
    required this.onSelectFilter,
    required this.editorImage,
    this.filterKey,
    super.key,
  });

  final FilterModel filterModel;
  final bool isSelected;
  final VoidCallback onSelectFilter;
  final Widget editorImage;
  final Key? filterKey;

  @override
  State<ImageEditorFilterBar> createState() => _ImageEditorFilterBarState();
}

class _ImageEditorFilterBarState extends State<ImageEditorFilterBar> {
  @override
  Widget build(BuildContext context) {
    return buildFilteredOptions(
      widget.editorImage,
      widget.isSelected,
      widget.filterModel.name,
      widget.onSelectFilter,
      widget.filterKey ?? ValueKey(widget.filterModel.name),
    );
  }

  Widget buildFilteredOptions(
    Widget editorImage,
    bool isSelected,
    String filterName,
    VoidCallback onSelectFilter,
    Key filterKey,
  ) {
    final colors = context.componentColors;
    return GestureDetector(
      onTap: () => onSelectFilter(),
      child: SizedBox(
        height: 90,
        width: 80,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            Container(
              height: 60,
              width: 60,
              decoration: ShapeDecoration(
                shape: SmoothRectangleBorder(
                  borderRadius: SmoothBorderRadius(
                    cornerRadius: 12,
                    cornerSmoothing: 0.6,
                  ),
                  side: BorderSide(
                    color: isSelected ? colors.primary : Colors.transparent,
                    width: 1.5,
                  ),
                ),
              ),
              child: Padding(
                padding: isSelected ? const EdgeInsets.all(2) : EdgeInsets.zero,
                child: ClipSmoothRect(
                  radius: SmoothBorderRadius(
                    cornerRadius: 9.69,
                    cornerSmoothing: 0.4,
                  ),
                  child: SizedBox(
                    height: isSelected ? 56 : 60,
                    width: isSelected ? 56 : 60,
                    child: editorImage,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              filterName,
              style: isSelected
                  ? TextStyles.bodyBold.copyWith(color: colors.textBase)
                  : TextStyles.body.copyWith(color: colors.textLight),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
