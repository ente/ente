import "package:flutter/widgets.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";

class RewindSvg extends StatelessWidget {
  const RewindSvg(this.asset, {this.fit = BoxFit.contain, super.key});

  static final _loaders = <String, SvgFileLoader>{};

  final String asset;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final file = RewindAssets.file(asset);
    return SvgPicture(
      _loaders.putIfAbsent(file.path, () => SvgFileLoader(file)),
      fit: fit,
    );
  }
}
