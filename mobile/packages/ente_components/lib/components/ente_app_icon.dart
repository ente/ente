import 'package:ente_components/theme/colors.dart';
import 'package:flutter/widgets.dart';

class EnteAppIcon extends StatelessWidget {
  const EnteAppIcon({super.key, required this.app, this.size = 24});

  final ComponentApp app;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: Image.asset(
        'assets/apps/${app.name}.png',
        package: 'ente_components',
        fit: BoxFit.contain,
      ),
    );
  }
}
