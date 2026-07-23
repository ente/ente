import "package:flutter/widgets.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/theme/ente_theme.dart";

class CollageLayoutHeading extends StatelessWidget {
  const CollageLayoutHeading({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 20, 0, 4),
        child: Text(
          AppLocalizations.of(context).collageLayout,
          style: TextStyle(color: getEnteColorScheme(context).textBase),
        ),
      ),
    );
  }
}

class CollageLayoutIconButton extends StatelessWidget {
  const CollageLayoutIconButton({
    super.key,
    required this.child,
    required this.onTap,
  });

  final Widget child;
  final void Function() onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.all(4), child: child),
    );
  }
}
