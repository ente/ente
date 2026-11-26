import "package:flutter/widgets.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/widgets/rewind_rive.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";

class RewindYearDuckies extends StatelessWidget {
  const RewindYearDuckies({super.key});

  static const _size = Size(390, 230);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox.fromSize(
          size: _size * RewindStage.scaleFor(constraints.biggest),
          child: const RewindDucky(RewindAssets.yearDuckies),
        ),
      ),
    );
  }
}
