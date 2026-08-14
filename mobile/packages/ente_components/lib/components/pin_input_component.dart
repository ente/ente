import 'package:ente_components/theme/colors.dart';
import 'package:ente_components/theme/motion.dart';
import 'package:ente_components/theme/radii.dart';
import 'package:ente_components/theme/text_styles.dart';
import 'package:ente_components/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=2275-11846&m=dev
// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=7634-53618&m=dev
class PinInputComponent extends StatefulWidget {
  const PinInputComponent({
    super.key,
    required this.controller,
    this.length = 6,
    this.autofocus = false,
    this.useNativeKeyboard = true,
    this.closeKeyboardWhenCompleted = true,
    this.obscureText = false,
    this.obscuringCharacter = '•',
    this.isError = false,
    this.isDisabled = false,
    this.autofillHints,
    this.semanticLabel,
    this.onChanged,
    this.onCompleted,
  }) : assert(length > 0),
       assert(obscuringCharacter.length == 1);

  final int length;
  final TextEditingController controller;
  final bool autofocus;
  // When false, the caller must update the controller from its own keypad.
  final bool useNativeKeyboard;
  final bool closeKeyboardWhenCompleted;
  final bool obscureText;
  final String obscuringCharacter;
  final bool isError;
  final bool isDisabled;
  final Iterable<String>? autofillHints;
  final String? semanticLabel;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCompleted;

  @override
  State<PinInputComponent> createState() => _PinInputComponentState();
}

class _PinInputComponentState extends State<PinInputComponent> {
  static const _boxWidth = 49.0;
  static const _boxHeight = 52.0;
  static const _boxGap = 6.0;

  final FocusNode _focusNode = FocusNode();
  String _value = '';
  String _lastControllerText = '';
  String? _lastCompletedValue;

  @override
  void initState() {
    super.initState();
    _synchronizeController();
    widget.controller.addListener(_handleControllerChanged);
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant PinInputComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      _synchronizeController();
      _lastCompletedValue = null;
      widget.controller.addListener(_handleControllerChanged);
    } else if (oldWidget.length != widget.length) {
      _synchronizeController();
      _lastCompletedValue = null;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    _focusNode.removeListener(_handleFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  String _visibleValue(String value) {
    if (value.length <= widget.length) {
      return value;
    }
    return value.substring(0, widget.length);
  }

  void _synchronizeController() {
    final controller = widget.controller;
    final controllerText = controller.text;
    final sanitizedText = _sanitizeValue(controllerText);
    _lastControllerText = controllerText;
    _value = sanitizedText;
    if (controllerText == sanitizedText) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.controller != controller) {
        return;
      }
      final currentText = controller.text;
      final sanitizedCurrentText = _sanitizeValue(currentText);
      if (currentText == sanitizedCurrentText) {
        return;
      }
      _lastControllerText = sanitizedCurrentText;
      if (_value != sanitizedCurrentText) {
        setState(() => _value = sanitizedCurrentText);
      }
      _replaceControllerText(sanitizedCurrentText);
    });
  }

  void _handleControllerChanged() {
    final controllerText = widget.controller.text;
    if (_lastControllerText == controllerText) {
      return;
    }
    final sanitizedText = _sanitizeValue(controllerText);
    if (sanitizedText != controllerText) {
      _replaceControllerText(sanitizedText);
      return;
    }
    _lastControllerText = controllerText;
    if (_value != controllerText && mounted) {
      setState(() => _value = controllerText);
    }
    widget.onChanged?.call(controllerText);
    if (widget.controller.text != controllerText) {
      return;
    }

    if (controllerText.length != widget.length) {
      _lastCompletedValue = null;
      return;
    }
    if (_lastCompletedValue == controllerText) {
      return;
    }
    _lastCompletedValue = controllerText;
    widget.onCompleted?.call(controllerText);
    if (widget.closeKeyboardWhenCompleted && mounted) {
      _focusNode.unfocus();
    }
  }

  String _sanitizeValue(String value) {
    final digits = value.replaceAll(RegExp('[^0-9]'), '');
    return _visibleValue(digits);
  }

  void _replaceControllerText(String value) {
    widget.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _handleFocusChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _moveSelectionToEnd() {
    if (widget.isDisabled) {
      return;
    }
    widget.controller.selection = TextSelection.collapsed(
      offset: widget.controller.text.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final desiredWidth =
        (_boxWidth * widget.length) + (_boxGap * (widget.length - 1));

    return SizedBox(
      height: _boxHeight,
      width: desiredWidth,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: SizedBox(
          width: desiredWidth,
          height: _boxHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ExcludeSemantics(child: _buildBoxes(context)),
              _buildTextField(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBoxes(BuildContext context) {
    final colors = context.componentColors;
    return Row(
      children: [
        for (var index = 0; index < widget.length; index++) ...[
          _PinInputBox(
            character: index < _value.length ? _value[index] : null,
            isFocused:
                _focusNode.hasFocus &&
                _value.length < widget.length &&
                index == _value.length,
            obscureText: widget.obscureText,
            obscuringCharacter: widget.obscuringCharacter,
            isError: widget.isError,
            isDisabled: widget.isDisabled,
            colors: colors,
          ),
          if (index != widget.length - 1) const SizedBox(width: _boxGap),
        ],
      ],
    );
  }

  Widget _buildTextField() {
    Widget field = TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      enabled: !widget.isDisabled,
      readOnly: !widget.useNativeKeyboard,
      showCursor: false,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.done,
      autofillHints: widget.autofillHints,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      obscureText: widget.obscureText,
      obscuringCharacter: widget.obscuringCharacter,
      maxLength: widget.length,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(widget.length),
      ],
      style: const TextStyle(color: Colors.transparent),
      cursorColor: Colors.transparent,
      decoration: const InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        counterText: '',
      ),
      onTap: _moveSelectionToEnd,
    );

    if (widget.semanticLabel != null) {
      field = Semantics(label: widget.semanticLabel, child: field);
    }
    return field;
  }
}

class _PinInputBox extends StatelessWidget {
  const _PinInputBox({
    required this.character,
    required this.isFocused,
    required this.obscureText,
    required this.obscuringCharacter,
    required this.isError,
    required this.isDisabled,
    required this.colors,
  });

  final String? character;
  final bool isFocused;
  final bool obscureText;
  final String obscuringCharacter;
  final bool isError;
  final bool isDisabled;
  final ColorTokens colors;

  bool get _isFilled => character != null;

  @override
  Widget build(BuildContext context) {
    final borderColor = switch ((isDisabled, isError, isFocused, _isFilled)) {
      (true, _, _, _) => colors.strokeFaint,
      (_, true, _, _) => colors.warning,
      (_, _, true, _) || (_, _, _, true) => colors.primary,
      _ => colors.strokeDark,
    };
    final borderWidth = isError || isFocused || _isFilled ? 2.0 : 1.0;
    final backgroundColor = switch ((isDisabled, _isFilled)) {
      (true, _) => colors.fillDark,
      (_, true) when !isError => colors.primaryLight,
      _ => colors.fillLight,
    };
    final textColor = switch ((isDisabled, isError)) {
      (true, _) => colors.textLight,
      (_, true) => colors.warning,
      _ => colors.primary,
    };

    return AnimatedContainer(
      duration: Motion.quick,
      curve: Curves.easeOut,
      width: _PinInputComponentState._boxWidth,
      height: _PinInputComponentState._boxHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border.all(color: borderColor, width: borderWidth),
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: AnimatedSwitcher(
        duration: Motion.quick,
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1).animate(animation),
              child: child,
            ),
          );
        },
        child: _buildCharacter(textColor),
      ),
    );
  }

  Widget? _buildCharacter(Color color) {
    if (character == null) {
      return null;
    }
    if (obscureText && obscuringCharacter == '•') {
      return Container(
        key: ValueKey(obscuringCharacter),
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
    }
    return Text(
      obscureText ? obscuringCharacter : character!,
      key: ValueKey(obscureText ? obscuringCharacter : character),
      style: TextStyles.h1.copyWith(color: color),
    );
  }
}
