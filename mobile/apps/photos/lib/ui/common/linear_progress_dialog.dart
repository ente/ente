import 'package:flutter/material.dart';
import 'package:photos/ente_theme_data.dart';
import "package:photos/theme/ente_theme.dart";

class LinearProgressDialog extends StatefulWidget {
  final String message;

  const LinearProgressDialog(this.message, {super.key});

  @override
  LinearProgressDialogState createState() => LinearProgressDialogState();
}

class LinearProgressDialogState extends State<LinearProgressDialog>
    with TickerProviderStateMixin {
  late AnimationController controller;
  late Tween<double> _tween;
  late Animation<double> _animation;

  double _target = 0.0;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      animationBehavior: AnimationBehavior.preserve,
    );

    _tween = Tween<double>(begin: _target, end: _target);

    _animation = _tween.animate(
      CurvedAnimation(curve: Curves.easeInOut, parent: controller),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void setProgress(double progress) {
    _target = progress;
    _tween.begin = _tween.end;
    controller.reset();
    _tween.end = progress;
    controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(
          widget.message,
          style: getEnteTextTheme(context).smallMuted,
          textAlign: TextAlign.center,
        ),
        content: AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return LinearProgressIndicator(
              value: _animation.value,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.greenAlternative,
              ),
            );
          },
        ),
      ),
    );
  }
}
