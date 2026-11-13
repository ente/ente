import 'package:ente_auth/theme/ente_theme.dart';
import 'package:ente_auth/ui/utils/icon_utils.dart';
import 'package:ente_auth/utils/totp_util.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/material.dart';

class CustomIconWidget extends StatelessWidget {
  final String iconData;

  CustomIconWidget({super.key, required this.iconData});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      width: 90,
      child: Stack(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: ShapeDecoration(
              shape: SmoothRectangleBorder(
                side: BorderSide(
                  width: 1.5,
                  color: getEnteColorScheme(
                    context,
                  ).tagChipSelectedColor.withValues(alpha: 0.5),
                ),
                borderRadius: SmoothBorderRadius(
                  cornerRadius: 15.5,
                  cornerSmoothing: 1.0,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: FittedBox(
              fit: BoxFit.contain,
              child: IconUtils.instance.getIcon(
                context,
                safeDecode(iconData).trim(),
                width: 50,
              ),
            ),
          ),
          _getEditIcon(context),
        ],
      ),
    );
  }

  Widget _getEditIcon(BuildContext context) {
    return Positioned(
      left: 60,
      top: 60,
      child: Center(
        child: Container(
          height: 28,
          width: 28,
          decoration: ShapeDecoration(
            color: Colors.white,
            shadows: const [
              BoxShadow(
                offset: Offset(0, 0),
                blurRadius: 0.84,
                color: Color.fromRGBO(0, 0, 0, 0.11),
              ),
              BoxShadow(
                offset: Offset(0.84, 0.84),
                blurRadius: 1.68,
                color: Color.fromRGBO(0, 0, 0, 0.09),
              ),
              BoxShadow(
                offset: Offset(2.53, 2.53),
                blurRadius: 2.53,
                color: Color.fromRGBO(0, 0, 0, 0.05),
              ),
              BoxShadow(
                offset: Offset(5.05, 4.21),
                blurRadius: 2.53,
                color: Color.fromRGBO(0, 0, 0, 0.02),
              ),
              BoxShadow(
                offset: Offset(7.58, 6.74),
                blurRadius: 2.53,
                color: Color.fromRGBO(0, 0, 0, 0.0),
              ),
            ],
            shape: SmoothRectangleBorder(
              borderRadius: SmoothBorderRadius(
                cornerRadius: 8,
                cornerSmoothing: 1.0,
              ),
            ),
          ),
          child: Icon(
            Icons.edit,
            size: 16,
            color: Colors.black.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}
