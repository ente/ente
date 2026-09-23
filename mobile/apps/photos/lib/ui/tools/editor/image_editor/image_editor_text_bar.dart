import "dart:math";

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/ui/tools/editor/image_editor/circular_icon_button.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_app_bar.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_color_picker.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_constants.dart";
import "package:pro_image_editor/core/models/styles/sub_editor_page_style.dart";
import "package:pro_image_editor/pro_image_editor.dart";

SubEditorPageStyle imageEditorSubEditorPageStyle(
  ValueGetter<SubEditor?> activeEditor,
) {
  return SubEditorPageStyle(
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(
          opacity: animation,
          child: activeEditor() == SubEditor.text
              ? MediaQuery.withNoTextScaling(child: child)
              : child,
        ),
  );
}

TextEditorConfigs imageEditorTextConfigs(BuildContext context) {
  final colors = context.componentColors;
  final textScaler = MediaQuery.textScalerOf(context);
  return TextEditorConfigs(
    enableTapOutsideToSave: false,
    initialPrimaryColor: Colors.white,
    initialSecondaryColor: Colors.black,
    initialBackgroundColorMode: LayerBackgroundMode.backgroundAndColor,
    customTextStyles: const [
      TextStyle(
        fontFamily:
            "packages/${TextStyles.fontPackage}/${TextStyles.fontFamily}",
      ),
      TextStyle(
        fontFamily:
            "packages/${TextStyles.fontPackage}/${TextStyles.outfitFontFamily}",
        fontWeight: FontWeight.w600,
      ),
      TextStyle(fontFamily: "packages/${TextStyles.fontPackage}/Gochi Hand"),
    ],
    style: TextEditorStyle(
      background: colors.specialScrim,
      inputCursorColor: colors.primary,
      inputHintColor: Colors.white70,
      textFieldMargin: EdgeInsets.zero,
    ),
    widgets: TextEditorWidgets(
      appBar: (editor, rebuildStream) => ReactiveAppbar(
        stream: rebuildStream,
        builder: (context) => PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: ImageEditorAppBar(
              configs: editor.configs,
              done: editor.done,
              close: editor.close,
            ),
          ),
        ),
      ),
      colorPicker: (_, _, _, _) => null,
      bottomBar: (editor, rebuildStream) => ReactiveWidget(
        stream: rebuildStream,
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: ImageEditorTextBar(editor: editor),
        ),
      ),
    ),
  );
}

enum _TextAction { color, font, background, align }

class ImageEditorTextBar extends StatefulWidget {
  const ImageEditorTextBar({super.key, required this.editor});

  final TextEditorState editor;

  @override
  State<ImageEditorTextBar> createState() => _ImageEditorTextBarState();
}

class _ImageEditorTextBarState extends State<ImageEditorTextBar> {
  _TextAction? _selectedAction;
  late double _textColorHue = _initialHue(widget.editor.primaryColor);
  late double _backgroundColorHue = _initialHue(widget.editor.secondaryColor);

  double _initialHue(Color color) {
    final hsv = HSVColor.fromColor(color);
    return hsv.saturation == 0 ? 0.5 : hsv.hue / 360;
  }

  void _selectAction(_TextAction action) {
    widget.editor.focusNode.unfocus();
    setState(() {
      _selectedAction = _selectedAction == action ? null : action;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final editor = widget.editor;
    final mediaQuery = MediaQuery.of(editor.context);
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    final maxToolbarHeight = max(
      0.0,
      mediaQuery.size.height -
          mediaQuery.viewPadding.vertical -
          keyboardHeight -
          kToolbarHeight -
          64,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardHeight),
      child: Material(
        color: context.componentColors.backgroundBase,
        child: SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxToolbarHeight),
            child: SingleChildScrollView(
              primary: false,
              child: Container(
                constraints: BoxConstraints(
                  minHeight: keyboardHeight > 0
                      ? 0
                      : min(editorBottomBarHeight, maxToolbarHeight),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minWidth: constraints.maxWidth,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _action(
                                _TextAction.color,
                                strings.color,
                                HugeIcons.strokeRoundedTextColor,
                              ),
                              _action(
                                _TextAction.font,
                                strings.font,
                                HugeIcons.strokeRoundedTextFont,
                              ),
                              _action(
                                _TextAction.background,
                                strings.background,
                                HugeIcons.strokeRoundedTextSquare,
                              ),
                              _action(
                                _TextAction.align,
                                strings.align,
                                switch (editor.align) {
                                  TextAlign.left =>
                                    HugeIcons.strokeRoundedTextAlignLeft,
                                  TextAlign.right =>
                                    HugeIcons.strokeRoundedTextAlignRight,
                                  _ => HugeIcons.strokeRoundedTextAlignCenter,
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (_selectedAction != null && keyboardHeight == 0) ...[
                      const SizedBox(height: 12),
                      switch (_selectedAction!) {
                        _TextAction.color => _buildColorPicker(),
                        _TextAction.font => _buildFontPicker(),
                        _TextAction.background => _buildBackgroundPicker(),
                        _TextAction.align => _buildAlignPicker(),
                      },
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _action(_TextAction action, String label, List<List<dynamic>> icon) {
    return CircularIconButton(
      label: label,
      hugeIcon: icon,
      size: 40,
      width: 90 * max(1, MediaQuery.textScalerOf(context).scale(14) / 14),
      isSelected: _selectedAction == action,
      onTap: () => _selectAction(action),
    );
  }

  Widget _buildColorPicker({bool forBackground = false}) {
    final editor = widget.editor;
    final color = (forBackground ? editor.secondaryColor : editor.primaryColor)
        .withValues(alpha: 1);
    final label = forBackground
        ? context.strings.imageEditorBackgroundColor
        : context.strings.imageEditorTextColor;

    void selectColor(Color value) {
      if (forBackground) {
        editor.secondaryColor = value.withValues(
          alpha: editor.secondaryColor.a,
        );
      } else {
        editor.primaryColor = value;
      }
    }

    void selectHue(double value) {
      setState(() {
        if (forBackground) {
          _backgroundColorHue = value;
        } else {
          _textColorHue = value;
        }
      });
      selectColor(HSVColor.fromAHSV(1, value * 360, 1, 1).toColor());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            label,
            style: TextStyles.mini.copyWith(
              color: context.componentColors.textLight,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(width: 12),
            for (final (swatch, swatchLabel) in [
              (Colors.white, context.strings.imageEditorWhite),
              (Colors.black, context.strings.black),
            ])
              _option(
                label: swatchLabel,
                isSelected: color == swatch,
                onTap: () => selectColor(swatch),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: swatch,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: context.componentColors.strokeFaint,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: ImageEditorColorPicker(
                value: forBackground ? _backgroundColorHue : _textColorHue,
                semanticLabel: label,
                onChangeStart: selectHue,
                onChanged: selectHue,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFontPicker() {
    final editor = widget.editor;
    return _optionsRow([
      for (final style in editor.textEditorConfigs.customTextStyles!)
        _option(
          label: style.fontFamily!.split('/').last,
          isSelected: editor.selectedTextStyle == style,
          onTap: () => editor.setTextStyle(style),
          child: Text(
            style.fontFamily!.split('/').last,
            style: style.copyWith(
              fontSize: 16,
              color: context.componentColors.textBase,
            ),
          ),
        ),
    ]);
  }

  Widget _buildBackgroundPicker() {
    final strings = context.strings;
    final editor = widget.editor;
    final colors = context.componentColors;
    final alpha = editor.secondaryColor.a;
    final selectedOpacity = alpha == 0 || alpha == 1 ? alpha : 0.5;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _optionsRow([
          for (final (opacity, label) in [
            (0.0, strings.imageEditorNoBackground),
            (1.0, strings.imageEditorSolidBackground),
            (0.5, strings.imageEditorTranslucentBackground),
          ])
            _option(
              label: label,
              isSelected: selectedOpacity == opacity,
              onTap: () => editor.secondaryColor = editor.secondaryColor
                  .withValues(alpha: opacity),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: colors.textBase.withValues(alpha: opacity),
                ),
                child: Text(
                  'Aa',
                  style: TextStyles.large.copyWith(
                    color: opacity == 0 ? colors.textBase : colors.textReverse,
                  ),
                ),
              ),
            ),
        ]),
        if (alpha > 0) ...[
          const SizedBox(height: 12),
          _buildColorPicker(forBackground: true),
        ],
      ],
    );
  }

  Widget _buildAlignPicker() {
    final strings = context.strings;
    final editor = widget.editor;
    return _optionsRow([
      for (final (alignment, icon, label) in [
        (
          TextAlign.left,
          HugeIcons.strokeRoundedTextAlignLeft,
          strings.imageEditorAlignLeft,
        ),
        (
          TextAlign.center,
          HugeIcons.strokeRoundedTextAlignCenter,
          strings.imageEditorAlignCenter,
        ),
        (
          TextAlign.right,
          HugeIcons.strokeRoundedTextAlignRight,
          strings.imageEditorAlignRight,
        ),
      ])
        _option(
          label: label,
          isSelected: editor.align == alignment,
          onTap: () => editor.setState(() => editor.align = alignment),
          child: HugeIcon(
            icon: icon,
            size: 22,
            color: context.componentColors.iconColor,
          ),
        ),
    ]);
  }

  Widget _optionsRow(List<Widget> children) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: max(0, constraints.maxWidth - 24),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: children,
          ),
        ),
      ),
    );
  }

  Widget _option({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required Widget child,
  }) {
    final colors = context.componentColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Semantics(
        button: true,
        selected: isSelected,
        label: label,
        child: Tooltip(
          message: label,
          excludeFromSemantics: true,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isSelected
                    ? colors.primary.withValues(alpha: 0.24)
                    : colors.fillLight,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isSelected ? colors.primary : colors.fillLight,
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: ExcludeSemantics(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
