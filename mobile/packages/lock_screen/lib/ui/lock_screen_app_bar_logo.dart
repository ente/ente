import 'package:ente_components/ente_components.dart';
import 'package:ente_lock_screen/lock_screen_settings.dart';
import 'package:ente_ui/theme/theme_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class LockScreenAppBarLogo extends StatelessWidget {
  const LockScreenAppBarLogo({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final settings = LockScreenSettings.instance;

    return SvgPicture.asset(
      settings.appLogoAsset,
      height: settings.appLogoHeight,
      colorFilter: ColorFilter.mode(
        AppThemeConfig.currentApp == EnteApp.auth
            ? colors.textBase
            : colors.primary,
        BlendMode.srcIn,
      ),
    );
  }
}
