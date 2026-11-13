import 'dart:async';

import 'package:flutter/material.dart';

enum ProgressDialogType { normal, download }

class ProgressDialog {
  final BuildContext _context;
  final ProgressDialogType _progressDialogType;
  final bool _barrierDismissible, _showLogs;
  final Widget? _customBody;
  final TextDirection _direction;
  final Color? _barrierColor;
  final _updates = ValueNotifier<int>(0);
  DialogRoute<void>? _route;

  String _dialogMessage = "Loading...";
  double _progress = 0.0, _maxProgress = 100.0;

  TextAlign _textAlign = TextAlign.left;
  Alignment _progressWidgetAlignment = Alignment.centerLeft;

  TextStyle _progressTextStyle = const TextStyle(
        color: Colors.black,
        fontSize: 12.0,
        fontWeight: FontWeight.w400,
      ),
      _messageStyle = const TextStyle(
        color: Colors.black,
        fontSize: 18.0,
        fontWeight: FontWeight.w600,
      );

  double _dialogElevation = 8.0, _borderRadius = 8.0;
  Color _backgroundColor = Colors.white;
  Curve _insetAnimCurve = Curves.easeInOut;
  EdgeInsets _dialogPadding = const EdgeInsets.all(8.0);

  Widget _progressWidget = Image.asset(
    'assets/double_ring_loading_io.gif',
    package: 'progress_dialog',
  );

  ProgressDialog(
    BuildContext context, {
    ProgressDialogType? type,
    bool? isDismissible,
    bool? showLogs,
    TextDirection? textDirection,
    Widget? customBody,
    Color? barrierColor,
  }) : _context = context,
       _progressDialogType = type ?? ProgressDialogType.normal,
       _barrierDismissible = isDismissible ?? true,
       _showLogs = showLogs ?? false,
       _customBody = customBody,
       _direction = textDirection ?? TextDirection.ltr,
       _barrierColor = barrierColor;

  void style({
    Widget? child,
    double? progress,
    double? maxProgress,
    String? message,
    Widget? progressWidget,
    Color? backgroundColor,
    TextStyle? progressTextStyle,
    TextStyle? messageTextStyle,
    double? elevation,
    TextAlign? textAlign,
    double? borderRadius,
    Curve? insetAnimCurve,
    EdgeInsets? padding,
    Alignment? progressWidgetAlignment,
  }) {
    if (isShowing()) return;
    if (_progressDialogType == ProgressDialogType.download) {
      _progress = progress ?? _progress;
    }

    _dialogMessage = message ?? _dialogMessage;
    _maxProgress = maxProgress ?? _maxProgress;
    _progressWidget = progressWidget ?? _progressWidget;
    _backgroundColor = backgroundColor ?? _backgroundColor;
    _messageStyle = messageTextStyle ?? _messageStyle;
    _progressTextStyle = progressTextStyle ?? _progressTextStyle;
    _dialogElevation = elevation ?? _dialogElevation;
    _borderRadius = borderRadius ?? _borderRadius;
    _insetAnimCurve = insetAnimCurve ?? _insetAnimCurve;
    _textAlign = textAlign ?? _textAlign;
    _progressWidget = child ?? _progressWidget;
    _dialogPadding = padding ?? _dialogPadding;
    _progressWidgetAlignment =
        progressWidgetAlignment ?? _progressWidgetAlignment;
  }

  void update({
    double? progress,
    double? maxProgress,
    String? message,
    Widget? progressWidget,
    TextStyle? progressTextStyle,
    TextStyle? messageTextStyle,
  }) {
    if (_progressDialogType == ProgressDialogType.download) {
      _progress = progress ?? _progress;
    }

    _dialogMessage = message ?? _dialogMessage;
    _maxProgress = maxProgress ?? _maxProgress;
    _progressWidget = progressWidget ?? _progressWidget;
    _messageStyle = messageTextStyle ?? _messageStyle;
    _progressTextStyle = progressTextStyle ?? _progressTextStyle;

    _updates.value++;
  }

  bool isShowing() {
    return _route?.isActive ?? false;
  }

  Future<bool> hide() async {
    final route = _route;
    if (route == null) return false;

    final navigator = route.navigator;
    final dismissed = navigator != null && route.isActive;
    if (dismissed) {
      if (route.isCurrent) {
        navigator.pop();
      } else {
        navigator.removeRoute(route);
      }
    }
    // Callers can navigate safely once the dialog's overlay is gone.
    await route.completed;
    if (_showLogs && dismissed) debugPrint('ProgressDialog dismissed');
    return dismissed;
  }

  Future<bool> show() async {
    if (isShowing() || !_context.mounted) return false;

    final navigator = Navigator.of(_context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: _context,
      themes: InheritedTheme.capture(from: _context, to: navigator.context),
      barrierDismissible: _barrierDismissible,
      barrierColor:
          _barrierColor ??
          DialogTheme.of(_context).barrierColor ??
          Colors.black54,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      builder: (_) => ListenableBuilder(
        listenable: _updates,
        builder: (_, _) => PopScope(
          canPop: _barrierDismissible,
          child: Dialog(
            backgroundColor: _backgroundColor,
            insetAnimationCurve: _insetAnimCurve,
            insetAnimationDuration: const Duration(milliseconds: 100),
            elevation: _dialogElevation,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(_borderRadius)),
            ),
            child: _buildBody(),
          ),
        ),
      ),
    );
    _route = route;
    unawaited(navigator.push(route));
    unawaited(
      route.completed.then((_) {
        if (identical(_route, route)) _route = null;
      }),
    );
    final animation = route.animation;
    do {
      await WidgetsBinding.instance.endOfFrame;
    } while (route.isActive && animation != null && animation.value == 0);
    if (_showLogs) debugPrint('ProgressDialog shown');
    return true;
  }

  Widget _buildBody() {
    final loader = Align(
      alignment: _progressWidgetAlignment,
      child: SizedBox(width: 60.0, height: 60.0, child: _progressWidget),
    );

    final text = Expanded(
      child: _progressDialogType == ProgressDialogType.normal
          ? Text(
              _dialogMessage,
              textAlign: _textAlign,
              style: _messageStyle,
              textDirection: _direction,
            )
          : Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const SizedBox(height: 8.0),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _dialogMessage,
                          style: _messageStyle,
                          textDirection: _direction,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4.0),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Text(
                      "$_progress/$_maxProgress",
                      style: _progressTextStyle,
                      textDirection: _direction,
                    ),
                  ),
                ],
              ),
            ),
    );

    return _customBody ??
        Container(
          padding: _dialogPadding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const SizedBox(width: 8.0),
                  _direction == TextDirection.ltr ? loader : text,
                  const SizedBox(width: 8.0),
                  _direction == TextDirection.rtl ? loader : text,
                  const SizedBox(width: 8.0),
                ],
              ),
            ],
          ),
        );
  }
}
