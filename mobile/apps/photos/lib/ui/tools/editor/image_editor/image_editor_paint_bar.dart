import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import "package:photos/generated/l10n.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_color_picker.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_configs_mixin.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_constants.dart";
import 'package:pro_image_editor/core/mixins/converted_configs.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

class ImageEditorPaintBar extends StatefulWidget with SimpleConfigsAccess {
  const ImageEditorPaintBar({
    super.key,
    required this.configs,
    required this.callbacks,
    required this.editor,
    required this.i18nColor,
  });

  final PaintEditorState editor;

  @override
  final ProImageEditorConfigs configs;
  @override
  final ProImageEditorCallbacks callbacks;

  final String i18nColor;

  @override
  State<ImageEditorPaintBar> createState() => _ImageEditorPaintBarState();
}

class _ImageEditorPaintBarState extends State<ImageEditorPaintBar>
    with ImageEditorConvertedConfigs, SimpleConfigsAccessState {
  double colorSliderValue = 0.5;
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
      height: editorBottomBarHeight,
      padding: EdgeInsets.zero,
      child: Align(
        alignment: Alignment.center,
        child: FadeInUp(
          duration: fadeInDuration,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(left: 20.0),
                child: Text(
                  AppLocalizations.of(context).brushColor,
                  style: TextStyles.large.copyWith(color: colors.textBase),
                ),
              ),
              const SizedBox(height: 24),
              ImageEditorColorPicker(
                value: colorSliderValue,
                onChanged: (value) {
                  setState(() {
                    colorSliderValue = value;
                  });
                  final hue = value * 360;
                  final color = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
                  widget.editor.setColor(color);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
