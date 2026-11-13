import 'package:ente_auth/theme/ente_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class AuthLogoWidget extends StatelessWidget {
  final double height;
  final Color? color;

  const AuthLogoWidget({super.key, this.height = 18, this.color});

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final logoColor = color ?? colorScheme.textBase;

    return SvgPicture.asset(
      'assets/svg/app-logo.svg',
      height: height,
      colorFilter: ColorFilter.mode(logoColor, BlendMode.srcIn),
    );
  }
}
