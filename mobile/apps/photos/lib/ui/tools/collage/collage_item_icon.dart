import "package:flutter/widgets.dart";
import "package:photos/theme/ente_theme.dart";

class CollageItemIcon extends StatelessWidget {
  const CollageItemIcon({super.key, this.isActive = false});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: isActive
              ? getEnteColorScheme(context).strokeBase
              : getEnteColorScheme(context).strokeMuted,
          width: 2,
        ),
        borderRadius: const BorderRadius.all(Radius.circular(2)),
      ),
    );
  }
}

class CollageIconContainerWidget extends StatelessWidget {
  const CollageIconContainerWidget({
    super.key,
    required this.child,
    this.width,
  });

  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(width: width ?? 40, child: child);
  }
}
