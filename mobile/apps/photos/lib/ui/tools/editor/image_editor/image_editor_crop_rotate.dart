import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import "package:flutter_svg/svg.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/ui/tools/editor/image_editor/circular_icon_button.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_configs_mixin.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_constants.dart";
import 'package:pro_image_editor/core/mixins/converted_configs.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

enum CropAspectRatioType {
  original(
    label: "Original",
    ratio: null,
    svg: "assets/image-editor/image-editor-crop-original.svg",
  ),
  free(
    label: "Free",
    ratio: null,
    svg: "assets/video-editor/video-crop-free-action.svg",
  ),
  square(
    label: "1:1",
    ratio: 1.0,
    svg: "assets/video-editor/video-crop-ratio_1_1-action.svg",
  ),
  widescreen(
    label: "16:9",
    ratio: 16.0 / 9.0,
    svg: "assets/video-editor/video-crop-ratio_16_9-action.svg",
  ),
  portrait(
    label: "9:16",
    ratio: 9.0 / 16.0,
    svg: "assets/video-editor/video-crop-ratio_9_16-action.svg",
  ),
  photo(
    label: "4:3",
    ratio: 4.0 / 3.0,
    svg: "assets/video-editor/video-crop-ratio_4_3-action.svg",
  ),
  photo_3_4(
    label: "3:4",
    ratio: 3.0 / 4.0,
    svg: "assets/video-editor/video-crop-ratio_3_4-action.svg",
  );

  const CropAspectRatioType({
    required this.label,
    required this.ratio,
    required this.svg,
  });

  final String label;
  final String svg;
  final double? ratio;
}

class ImageEditorCropRotateBar extends StatefulWidget with SimpleConfigsAccess {
  const ImageEditorCropRotateBar({
    super.key,
    required this.configs,
    required this.callbacks,
    required this.editor,
  });
  final CropRotateEditorState editor;

  @override
  final ProImageEditorConfigs configs;

  @override
  final ProImageEditorCallbacks callbacks;

  @override
  State<ImageEditorCropRotateBar> createState() =>
      _ImageEditorCropRotateBarState();
}

class _ImageEditorCropRotateBarState extends State<ImageEditorCropRotateBar>
    with ImageEditorConvertedConfigs, SimpleConfigsAccessState {
  CropAspectRatioType selectedAspectRatio = CropAspectRatioType.original;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [_buildFunctions(constraints)],
        );
      },
    );
  }

  Widget _buildFunctions(BoxConstraints constraints) {
    final colors = context.componentColors;
    return BottomAppBar(
      color: colors.backgroundBase,
      padding: EdgeInsets.zero,
      height: editorBottomBarHeight,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FadeInUp(
          duration: fadeInDuration,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularIconButton(
                    hugeIcon: HugeIcons.strokeRoundedRotateCrop,
                    label: AppLocalizations.of(context).rotate,
                    onTap: () {
                      widget.editor.rotate();
                    },
                  ),
                  const SizedBox(width: 6),
                  CircularIconButton(
                    hugeIcon: HugeIcons.strokeRoundedFlipLeft,
                    label: AppLocalizations.of(context).flip,
                    onTap: () {
                      widget.editor.flip();
                    },
                  ),
                ],
              ),
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: CropAspectRatioType.values.length,
                  itemBuilder: (context, index) {
                    final aspectRatio = CropAspectRatioType.values[index];
                    final isSelected = selectedAspectRatio == aspectRatio;
                    return Padding(
                      padding: const EdgeInsets.only(left: 6.0, right: 6.0),
                      child: CropAspectChip(
                        label: aspectRatio.label,
                        svg: aspectRatio.svg,
                        isSelected: isSelected,
                        onTap: () {
                          setState(() {
                            selectedAspectRatio = aspectRatio;
                          });
                          widget.editor.updateAspectRatio(
                            aspectRatio.ratio ?? -1,
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CropAspectChip extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final String? svg;
  final bool isSelected;
  final VoidCallback? onTap;

  const CropAspectChip({
    super.key,
    this.label,
    this.icon,
    this.svg,
    required this.isSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final selectedBackground = colors.fillBase.withValues(alpha: 0.9);
    final selectedForeground = colors.textReverse;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? selectedBackground : colors.fillLight,
          borderRadius: BorderRadius.circular(25),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (svg != null) ...[
              SvgPicture.asset(
                svg!,
                height: 32,
                colorFilter: ColorFilter.mode(
                  isSelected ? selectedForeground : colors.iconColor,
                  BlendMode.srcIn,
                ),
              ),
            ],
            const SizedBox(width: 4),
            if (label != null)
              Text(
                label!,
                style: TextStyles.body.copyWith(
                  color: isSelected ? selectedForeground : colors.iconColor,
                ),
              ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }
}
