import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Requests focus and explicitly shows Android's soft keyboard for text input.
///
/// Flutter can mark a text field as focused during a route/app-launch
/// transition without Android showing the IME. This is visible on launch-time
/// app lock screens: the password field is focused, but the keyboard stays
/// hidden. This wrapper waits until the field is attached, focuses the provided
/// [focusNode], then asks the platform text input channel to show the keyboard.
/// See https://github.com/flutter/flutter/issues/122994 for the upstream
/// Flutter issue tracking this behavior.
///
/// Use this only for text inputs that intentionally need keyboard focus as soon
/// as they appear. The same [focusNode] must be passed to the wrapped text field.
class AndroidTextInputAutofocus extends StatefulWidget {
  const AndroidTextInputAutofocus({
    super.key,
    required this.focusNode,
    required this.child,
    this.enabled = true,
  });

  final FocusNode focusNode;
  final Widget child;
  final bool enabled;

  @override
  State<AndroidTextInputAutofocus> createState() =>
      _AndroidTextInputAutofocusState();
}

class _AndroidTextInputAutofocusState extends State<AndroidTextInputAutofocus> {
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _scheduleFocus();
  }

  @override
  void didUpdateWidget(AndroidTextInputAutofocus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.enabled && widget.enabled) {
      _scheduleFocus();
    }
  }

  @override
  void dispose() {
    _token++;
    super.dispose();
  }

  void _scheduleFocus() {
    if (!Platform.isAndroid || !widget.enabled) {
      return;
    }
    unawaited(_focusAndShowKeyboard(++_token));
  }

  Future<void> _focusAndShowKeyboard(int token) async {
    bool isValid() => mounted && token == _token && widget.enabled;

    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (!isValid()) return;

    widget.focusNode.requestFocus();

    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!isValid() || !widget.focusNode.hasFocus) return;

    await SystemChannels.textInput.invokeMethod<void>('TextInput.show');

    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!isValid() || !widget.focusNode.hasFocus) return;

    await SystemChannels.textInput.invokeMethod<void>('TextInput.show');
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
