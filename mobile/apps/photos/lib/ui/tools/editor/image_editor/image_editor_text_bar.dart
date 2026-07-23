import "package:ente_components/ente_components.dart";
import 'package:flutter/material.dart';
import "package:hugeicons/hugeicons.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/ui/tools/editor/image_editor/circular_icon_button.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_color_picker.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_configs_mixin.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_constants.dart";
import 'package:pro_image_editor/core/mixins/converted_configs.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

class ImageEditorTextBar extends StatefulWidget with SimpleConfigsAccess {
  const ImageEditorTextBar({
    super.key,
    required this.configs,
    required this.callbacks,
    required this.editor,
  });

  final TextEditorState editor;

  @override
  final ProImageEditorConfigs configs;
  @override
  final ProImageEditorCallbacks callbacks;

  @override
  State<ImageEditorTextBar> createState() => _ImageEditorTextBarState();
}

class _ImageEditorTextBarState extends State<ImageEditorTextBar>
    with ImageEditorConvertedConfigs, SimpleConfigsAccessState {
  int selectedActionIndex = -1;
  double colorSliderValue = 0.5;

  void _selectAction(int index) {
    setState(() {
      selectedActionIndex = selectedActionIndex == index ? -1 : index;
    });
  }

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
    return BottomAppBar(
      padding: EdgeInsets.zero,
      height: editorBottomBarHeight,
      child: FadeInUp(
        duration: fadeInDuration,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: <Widget>[_buildMainActionButtons(), _buildHelperWidget()],
        ),
      ),
    );
  }

  Widget _buildMainActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        CircularIconButton(
          hugeIcon: HugeIcons.strokeRoundedTextColor,
          label: AppLocalizations.of(context).color,
          isSelected: selectedActionIndex == 0,
          onTap: () {
            _selectAction(0);
          },
        ),
        CircularIconButton(
          hugeIcon: HugeIcons.strokeRoundedTextFont,
          label: AppLocalizations.of(context).font,
          isSelected: selectedActionIndex == 1,
          onTap: () {
            _selectAction(1);
          },
        ),
        CircularIconButton(
          hugeIcon: HugeIcons.strokeRoundedTextSquare,
          label: AppLocalizations.of(context).background,
          isSelected: selectedActionIndex == 2,
          onTap: () {
            setState(() {
              selectedActionIndex = 2;
            });
          },
        ),
        CircularIconButton(
          hugeIcon: HugeIcons.strokeRoundedTextAlignLeft,
          label: AppLocalizations.of(context).align,
          isSelected: selectedActionIndex == 3,
          onTap: () {
            setState(() {
              selectedActionIndex = 3;
            });
          },
        ),
      ],
    );
  }

  Widget _buildHelperWidget() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
      child: switch (selectedActionIndex) {
        0 => ImageEditorColorPicker(
          value: colorSliderValue,
          onChanged: (value) {
            setState(() {
              colorSliderValue = value;
            });
            final hue = value * 360;
            final color = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
            widget.editor.primaryColor = color;
          },
        ),
        1 => _FontPickerWidget(editor: widget.editor),
        2 => _BackgroundPickerWidget(editor: widget.editor),
        3 => _AlignPickerWidget(editor: widget.editor),
        _ => const SizedBox.shrink(),
      },
    );
  }
}

class _FontPickerWidget extends StatelessWidget {
  final TextEditorState editor;

  const _FontPickerWidget({required this.editor});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final selectedBackground = colors.fillBase.withValues(alpha: 0.9);
    if (editor.textEditorConfigs.customTextStyles == null) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: editor.textEditorConfigs.customTextStyles!.asMap().entries.map((
        entry,
      ) {
        final item = entry.value;
        final selected = editor.selectedTextStyle;
        final bool isSelected = selected.hashCode == item.hashCode;

        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: GestureDetector(
            onTap: () {
              editor.setTextStyle(item);
            },
            child: Container(
              height: 40,
              width: 48,
              decoration: BoxDecoration(
                color: isSelected ? selectedBackground : colors.fillLight,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Center(
                child: Text(
                  'Aa',
                  style: item.copyWith(
                    color: isSelected ? colors.textReverse : colors.iconColor,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _BackgroundPickerWidget extends StatelessWidget {
  final TextEditorState editor;

  const _BackgroundPickerWidget({required this.editor});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final faintFill = colors.fillBase.withValues(
      alpha: isLightMode ? 0.04 : 0.12,
    );
    final backgroundStyles = {
      LayerBackgroundMode.background: {
        'text': 'Aa',
        'selectedBackgroundColor': isLightMode ? faintFill : Colors.white,
        'backgroundColor': colors.fillLight,
        'border': null,
        'textColor': Colors.white,
        'selectedInnerBackgroundColor': Colors.black,
        'innerBackgroundColor': Colors.transparent,
      },
      LayerBackgroundMode.backgroundAndColor: {
        'text': 'Aa',
        'selectedBackgroundColor': isLightMode ? faintFill : Colors.white,
        'backgroundColor': colors.fillLight,
        'border': null,
        'textColor': Colors.black,
        'selectedInnerBackgroundColor': Colors.transparent,
        'innerBackgroundColor': Colors.transparent,
      },
      LayerBackgroundMode.backgroundAndColorWithOpacity: {
        'text': 'Aa',
        'selectedBackgroundColor': isLightMode ? faintFill : Colors.white,
        'backgroundColor': colors.fillLight,
        'border': null,
        'textColor': Colors.black,
        'selectedInnerBackgroundColor': Colors.black.withValues(alpha: 0.11),
        'innerBackgroundColor': isLightMode
            ? Colors.black.withValues(alpha: 0.11)
            : Colors.white.withValues(alpha: 0.11),
      },
      LayerBackgroundMode.onlyColor: {
        'text': 'Aa',
        'selectedBackgroundColor': isLightMode ? faintFill : Colors.black,
        'backgroundColor': colors.fillLight,
        'border': isLightMode
            ? null
            : Border.all(color: Colors.white, width: 2),
        'textColor': Colors.black,
        'selectedInnerBackgroundColor': Colors.white,
        'innerBackgroundColor': Colors.white.withValues(alpha: 0.6),
      },
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: backgroundStyles.entries.map((entry) {
        final mode = entry.key;
        final style = entry.value;
        final isSelected = editor.backgroundColorMode == mode;

        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: GestureDetector(
            onTap: () {
              editor.setState(() {
                editor.backgroundColorMode = mode;
              });
            },
            child: SizedBox(
              height: 40,
              width: 48,
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected
                      ? style['selectedBackgroundColor'] as Color
                      : style['backgroundColor'] as Color,
                  borderRadius: BorderRadius.circular(25),
                  border: isSelected ? style['border'] as Border? : null,
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Center(
                      child: Container(
                        height: 20,
                        width: 22,
                        decoration: ShapeDecoration(
                          color: isSelected
                              ? style['selectedInnerBackgroundColor'] as Color
                              : style['innerBackgroundColor'] as Color,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: Text(
                        style['text'] as String,
                        style: TextStyle(
                          color: isSelected
                              ? style['textColor'] as Color
                              : colors.iconColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _AlignPickerWidget extends StatelessWidget {
  final TextEditorState editor;

  const _AlignPickerWidget({required this.editor});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final selectedBackground = colors.fillBase.withValues(alpha: 0.9);
    final alignments = <(TextAlign, List<List<dynamic>>)>[
      (TextAlign.left, HugeIcons.strokeRoundedTextAlignLeft),
      (TextAlign.center, HugeIcons.strokeRoundedTextAlignCenter),
      (TextAlign.right, HugeIcons.strokeRoundedTextAlignRight),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: alignments.map((alignmentData) {
        final (alignment, hugeIcon) = alignmentData;
        final isSelected = editor.align == alignment;

        return Padding(
          padding: const EdgeInsets.only(right: 12.0),
          child: GestureDetector(
            onTap: () {
              editor.setState(() {
                editor.align = alignment;
              });
            },
            child: Container(
              height: 40,
              width: 48,
              decoration: BoxDecoration(
                color: isSelected ? selectedBackground : colors.fillLight,
                borderRadius: BorderRadius.circular(25),
                border: isSelected
                    ? Border.all(color: Colors.black, width: 2)
                    : null,
              ),
              child: Center(
                child: HugeIcon(
                  icon: hugeIcon,
                  size: 22,
                  color: isSelected ? colors.textReverse : colors.iconColor,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
