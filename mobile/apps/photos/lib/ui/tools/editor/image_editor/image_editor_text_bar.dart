import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_app_bar.dart";
import "package:photos/ui/tools/editor/image_editor/image_editor_color_picker.dart";
import "package:pro_image_editor/core/models/styles/sub_editor_page_style.dart";
import "package:pro_image_editor/pro_image_editor.dart";

SubEditorPageStyle imageEditorSubEditorPageStyle(
  ValueGetter<SubEditor?> activeEditor,
) {
  return SubEditorPageStyle(
    positionTop: 0,
    positionBottom: 0,
    positionLeft: 0,
    positionRight: 0,
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
        fontWeight: FontWeight.w500,
      ),
      TextStyle(fontFamily: "packages/${TextStyles.fontPackage}/Gochi Hand"),
    ],
    inputTextFieldAlign: Alignment.topCenter,
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

class ImageEditorTextPage extends TextEditor {
  const ImageEditorTextPage({
    super.key,
    super.heroTag,
    super.layer,
    super.configs,
    super.callbacks,
    super.imageSize,
    required super.theme,
  });

  @override
  TextEditorState createState() => _ImageEditorTextPageState();
}

class _ImageEditorTextPageState extends TextEditorState {
  late TextEditorConfigs _textConfigs = widget.configs.textEditor;

  @override
  TextEditorConfigs get textEditorConfigs => _textConfigs;

  @override
  Widget build(BuildContext context) {
    final configs = widget.configs.textEditor;
    _textConfigs = configs.copyWith(
      style: configs.style.copyWith(
        textFieldPadding: EdgeInsets.only(
          top: MediaQuery.orientationOf(context) == Orientation.landscape
              ? 0
              : MediaQuery.sizeOf(context).height * _textFieldTopFraction,
        ),
      ),
    );
    return super.build(context);
  }
}

const _textFieldTopFraction = 0.12;
const _controlSize = 48.0;
const _rowHeight = 48.0;
const _pillRadius = 25.0;
const _fontMenuWidth = 196.0;
const _fontMenuItemHeight = 52.0;
const _hueColors = [
  Color(0xFFFF0000),
  Color(0xFFFFFF00),
  Color(0xFF00FF00),
  Color(0xFF00FFFF),
  Color(0xFF0000FF),
  Color(0xFFFF00FF),
  Color(0xFFFF0000),
];

enum _ColorTarget { text, background }

class ImageEditorTextBar extends StatefulWidget {
  const ImageEditorTextBar({super.key, required this.editor});

  final TextEditorState editor;

  @override
  State<ImageEditorTextBar> createState() => _ImageEditorTextBarState();
}

class _ImageEditorTextBarState extends State<ImageEditorTextBar> {
  final _fontMenu = OverlayPortalController();
  var _colorTarget = _ColorTarget.text;
  var _showHueSlider = false;
  var _swatchesAtStart = true;
  var _swatchesAtEnd = true;
  late double _textColorHue = _initialHue(widget.editor.primaryColor);
  late double _backgroundColorHue = _initialHue(widget.editor.secondaryColor);

  TextEditorState get _editor => widget.editor;

  List<TextStyle> get _fonts => _editor.textEditorConfigs.customTextStyles!;

  TextStyle get _font => _fonts.firstWhere(
    (font) => font.fontFamily == _editor.selectedTextStyle.fontFamily,
    orElse: () => _fonts.first,
  );

  bool get _isBold => _editor.selectedTextStyle.fontWeight == FontWeight.w700;

  bool get _isItalic => _editor.selectedTextStyle.fontStyle == FontStyle.italic;

  bool get _forBackground => _colorTarget == _ColorTarget.background;

  Color get _color =>
      (_forBackground ? _editor.secondaryColor : _editor.primaryColor)
          .withValues(alpha: 1);

  double _initialHue(Color color) {
    final hsv = HSVColor.fromColor(color);
    return hsv.saturation == 0 ? 0.5 : hsv.hue / 360;
  }

  String _fontName(TextStyle font) => font.fontFamily!.split('/').last;

  void _setTextStyle({TextStyle? font, bool? bold, bool? italic}) {
    _editor.setTextStyle(
      (font ?? _font).copyWith(
        fontWeight: (bold ?? _isBold) ? FontWeight.w700 : null,
        fontStyle: (italic ?? _isItalic) ? FontStyle.italic : null,
      ),
    );
  }

  void _toggleFontMenu() => setState(_fontMenu.toggle);

  void _selectColor(Color value) {
    if (_forBackground) {
      _editor.secondaryColor = value.withValues(
        alpha: _editor.secondaryColor.a,
      );
    } else {
      _editor.primaryColor = value;
    }
  }

  void _selectHue(double value) {
    setState(() {
      if (_forBackground) {
        _backgroundColorHue = value;
      } else {
        _textColorHue = value;
      }
    });
    _selectColor(HSVColor.fromAHSV(1, value * 360, 1, 1).toColor());
  }

  void _selectColorTarget(_ColorTarget target) {
    if (target == _ColorTarget.background && _editor.secondaryColor.a == 0) {
      _editor.secondaryColor = _editor.secondaryColor.withValues(alpha: 1);
    }
    setState(() => _colorTarget = target);
  }

  void _cycleBackground() {
    final alpha = _editor.secondaryColor.a;
    final next = alpha == 0
        ? 1.0
        : alpha == 1
        ? 0.5
        : 0.0;
    _editor.secondaryColor = _editor.secondaryColor.withValues(alpha: next);
    if (next == 0) setState(() => _colorTarget = _ColorTarget.text);
  }

  void _toggleHueSlider() {
    setState(() {
      _showHueSlider = !_showHueSlider;
      _textColorHue = _initialHue(_editor.primaryColor);
      _backgroundColorHue = _initialHue(_editor.secondaryColor);
    });
  }

  bool _updateSwatchFades(ScrollMetrics metrics) {
    final atStart = metrics.extentBefore <= 0;
    final atEnd = metrics.extentAfter <= 0;
    if (atStart != _swatchesAtStart || atEnd != _swatchesAtEnd) {
      setState(() {
        _swatchesAtStart = atStart;
        _swatchesAtEnd = atEnd;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(_editor.context).viewInsets.bottom,
      ),
      child: Material(
        color: context.componentColors.backgroundBase,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: Spacing.md,
              vertical: landscape ? 0 : Spacing.sm,
            ),
            child: landscape
                ? SizedBox(
                    height: _rowHeight,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        SizedBox(width: 320, child: _buildStyleRow(context)),
                        const SizedBox(width: Spacing.md),
                        SizedBox(width: 320, child: _buildColorRow(context)),
                      ],
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: _rowHeight,
                        child: _buildStyleRow(context),
                      ),
                      const SizedBox(height: Spacing.lg),
                      SizedBox(
                        height: _rowHeight,
                        child: _buildColorRow(context),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildStyleRow(BuildContext context) {
    final strings = context.strings;
    final (alignLabel, alignIcon) = switch (_editor.align) {
      TextAlign.left => (
        strings.imageEditorAlignLeft,
        HugeIcons.strokeRoundedTextAlignLeft,
      ),
      TextAlign.right => (
        strings.imageEditorAlignRight,
        HugeIcons.strokeRoundedTextAlignRight,
      ),
      _ => (
        strings.imageEditorAlignCenter,
        HugeIcons.strokeRoundedTextAlignCenter,
      ),
    };
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: _buildFontButton(context),
          ),
        ),
        const SizedBox(width: Spacing.sm),
        _BarButton(
          label: strings.imageEditorBold,
          icon: HugeIcons.strokeRoundedTextBold,
          isSelected: _isBold,
          onTap: () => _setTextStyle(bold: !_isBold),
        ),
        const SizedBox(width: Spacing.sm),
        _BarButton(
          label: strings.imageEditorItalic,
          icon: HugeIcons.strokeRoundedTextItalic,
          isSelected: _isItalic,
          onTap: () => _setTextStyle(italic: !_isItalic),
        ),
        const SizedBox(width: Spacing.sm),
        _BarButton(
          label: alignLabel,
          icon: alignIcon,
          onTap: _editor.toggleTextAlign,
        ),
        const SizedBox(width: Spacing.sm),
        _buildBackgroundButton(context),
      ],
    );
  }

  Widget _buildFontButton(BuildContext context) {
    final colors = context.componentColors;
    final isOpen = _fontMenu.isShowing;
    final name = _fontName(_font);
    return Semantics(
      button: true,
      label: context.strings.font,
      value: name,
      onTap: _toggleFontMenu,
      child: GestureDetector(
        onTap: _toggleFontMenu,
        behavior: HitTestBehavior.opaque,
        child: Center(
          widthFactor: 1,
          child: OverlayPortal.overlayChildLayoutBuilder(
            controller: _fontMenu,
            overlayChildBuilder: _buildFontMenu,
            child: Container(
              height: _controlSize,
              padding: const EdgeInsetsDirectional.only(
                start: Spacing.lg,
                end: Spacing.md,
              ),
              decoration: BoxDecoration(
                color: isOpen
                    ? colors.fillBase.withValues(alpha: 0.9)
                    : colors.fillLight,
                borderRadius: BorderRadius.circular(_pillRadius),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _font.copyWith(
                        inherit: false,
                        fontSize: TextStyles.body.fontSize,
                        height: TextStyles.body.height,
                        color: isOpen ? colors.textReverse : colors.iconColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  HugeIcon(
                    icon: isOpen
                        ? HugeIcons.strokeRoundedArrowDown01
                        : HugeIcons.strokeRoundedArrowUp01,
                    size: IconSizes.tiny,
                    color: isOpen ? colors.textReverse : colors.textLight,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFontMenu(BuildContext context, OverlayChildLayoutInfo info) {
    final colors = context.componentColors;
    final borderSide = BorderSide(color: colors.strokeFaint);
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final padding = MediaQueryData.fromView(View.of(context)).padding;
    final button = MatrixUtils.transformRect(
      info.childPaintTransform,
      Offset.zero & info.childSize,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleFontMenu,
          ),
        ),
        Positioned(
          left: (isRtl ? button.right - _fontMenuWidth : button.left).clamp(
            padding.left + Spacing.sm,
            info.overlaySize.width -
                padding.right -
                _fontMenuWidth -
                Spacing.sm,
          ),
          bottom: info.overlaySize.height - button.top + Spacing.sm,
          child: Material(
            color: colors.fillLight,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              side: borderSide,
              borderRadius: BorderRadius.circular(Radii.button),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: (button.top - padding.top - Spacing.sm).clamp(
                  0.0,
                  _fontMenuItemHeight * 4.5,
                ),
              ),
              child: SizedBox(
                width: _fontMenuWidth,
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (final font in _fonts)
                      _buildFontOption(context, font, borderSide),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFontOption(
    BuildContext context,
    TextStyle font,
    BorderSide borderSide,
  ) {
    final colors = context.componentColors;
    final isSelected = font == _font;
    return Semantics(
      button: true,
      selected: isSelected,
      child: InkWell(
        onTap: () {
          _setTextStyle(font: font);
          _toggleFontMenu();
        },
        child: Container(
          height: _fontMenuItemHeight,
          padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
          decoration: BoxDecoration(
            border: font == _fonts.last ? null : Border(bottom: borderSide),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: ExcludeSemantics(
                  child: Text(
                    'Aa',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: font.copyWith(
                      inherit: false,
                      fontSize: TextStyles.body.fontSize,
                      height: TextStyles.body.height,
                      color: colors.textBase,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _fontName(font),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyles.mini.copyWith(color: colors.textBase),
                ),
              ),
              if (isSelected)
                HugeIcon(
                  icon: HugeIcons.strokeRoundedTick02,
                  size: IconSizes.small,
                  color: colors.iconColor,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundButton(BuildContext context) {
    final strings = context.strings;
    final colors = context.componentColors;
    final background = _editor.secondaryColor;
    final label = background.a == 0
        ? strings.imageEditorNoBackground
        : background.a == 1
        ? strings.imageEditorSolidBackground
        : strings.imageEditorTranslucentBackground;
    final isDark =
        ThemeData.estimateBrightnessForColor(background.withValues(alpha: 1)) ==
        Brightness.dark;
    return _BarButton(
      label: label,
      onTap: _cycleBackground,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(Radii.xs),
        ),
        child: Text(
          'Aa',
          maxLines: 1,
          softWrap: false,
          style: TextStyles.bodyBold.copyWith(
            color: background.a == 0
                ? colors.iconColor
                : isDark
                ? Colors.white
                : Colors.black,
          ),
        ),
      ),
    );
  }

  Widget _buildColorRow(BuildContext context) {
    final strings = context.strings;
    final colors = context.componentColors;
    final label = _forBackground
        ? strings.imageEditorBackgroundColor
        : strings.imageEditorTextColor;
    return Row(
      children: [
        Container(
          height: _controlSize,
          padding: EdgeInsets.zero,
          decoration: BoxDecoration(
            color: colors.fillLight,
            borderRadius: BorderRadius.circular(_pillRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (target, targetLabel, icon) in [
                (
                  _ColorTarget.text,
                  strings.imageEditorTextColor,
                  HugeIcons.strokeRoundedTextColor,
                ),
                (
                  _ColorTarget.background,
                  strings.imageEditorBackgroundColor,
                  HugeIcons.strokeRoundedTextSquare,
                ),
              ])
                _BarButton(
                  label: targetLabel,
                  icon: icon,
                  isSelected: _colorTarget == target,
                  size: const Size.square(_controlSize),
                  restingColor: Colors.transparent,
                  onTap: () => _selectColorTarget(target),
                ),
            ],
          ),
        ),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: _showHueSlider
              ? ImageEditorColorPicker(
                  value: _forBackground ? _backgroundColorHue : _textColorHue,
                  semanticLabel: label,
                  onChangeStart: _selectHue,
                  onChanged: _selectHue,
                  padding: EdgeInsets.zero,
                )
              : _buildSwatches(context),
        ),
        const SizedBox(width: Spacing.sm),
        _buildHueSliderButton(context),
      ],
    );
  }

  List<(Color, String)> _swatches(BuildContext context) {
    final strings = context.strings;
    final colors = context.componentColors;
    return [
      (Colors.black, strings.black),
      (Colors.white, strings.imageEditorWhite),
      (colors.blue, strings.imageEditorBlue),
      (colors.warning, strings.imageEditorRed),
      (colors.green, strings.imageEditorGreen),
      (colors.caution, strings.imageEditorOrange),
      (colors.accentPink, strings.imageEditorPink),
      (colors.accentTeal, strings.imageEditorTeal),
      (colors.purple, strings.imageEditorPurple),
    ];
  }

  Widget _buildSwatches(BuildContext context) {
    final colors = context.componentColors;
    return Container(
      height: _controlSize,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colors.fillLight,
        borderRadius: BorderRadius.circular(_pillRadius),
      ),
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) =>
            _updateSwatchFades(notification.metrics),
        child: NotificationListener<ScrollUpdateNotification>(
          onNotification: (notification) =>
              _updateSwatchFades(notification.metrics),
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => LinearGradient(
              begin: AlignmentDirectional.centerStart,
              end: AlignmentDirectional.centerEnd,
              colors: [
                _swatchesAtStart ? Colors.white : Colors.transparent,
                Colors.white,
                Colors.white,
                _swatchesAtEnd ? Colors.white : Colors.transparent,
              ],
              stops: const [0, 0.1, 0.9, 1],
            ).createShader(rect, textDirection: Directionality.of(context)),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
              children: [
                for (final (swatch, name) in _swatches(context))
                  _Swatch(
                    color: swatch,
                    label: name,
                    isSelected: _color == swatch,
                    onTap: () => _selectColor(swatch),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHueSliderButton(BuildContext context) {
    final strings = context.strings;
    if (_showHueSlider) {
      return _BarButton(
        label: strings.close,
        icon: HugeIcons.strokeRoundedCancel01,
        onTap: _toggleHueSlider,
      );
    }
    return _BarButton(
      label: strings.imageEditorCustomColor,
      onTap: _toggleHueSlider,
      child: _SwatchRing(
        isSelected: !_swatches(context).any((swatch) => swatch.$1 == _color),
        child: const DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(colors: _hueColors),
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.child,
    this.isSelected,
    this.size = const Size.square(_controlSize),
    this.restingColor,
  });

  final String label;
  final VoidCallback onTap;
  final List<List<dynamic>>? icon;
  final Widget? child;
  final bool? isSelected;
  final Size size;
  final Color? restingColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final isSelected = this.isSelected ?? false;
    return Semantics(
      button: true,
      selected: this.isSelected,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Center(
            widthFactor: 1,
            child: Container(
              width: size.width,
              height: size.height,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected
                    ? colors.fillBase.withValues(alpha: 0.9)
                    : restingColor ?? colors.fillLight,
                borderRadius: BorderRadius.circular(_pillRadius),
              ),
              child:
                  child ??
                  HugeIcon(
                    icon: icon!,
                    size: IconSizes.small,
                    color: isSelected ? colors.textReverse : colors.iconColor,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      onTap: onTap,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: _controlSize,
            child: Center(
              child: _SwatchRing(
                isSelected: isSelected,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: context.componentColors.strokeFaint,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwatchRing extends StatelessWidget {
  const _SwatchRing({required this.isSelected, required this.child});

  final bool isSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isSelected
              ? context.componentColors.fillBase
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: child,
    );
  }
}
