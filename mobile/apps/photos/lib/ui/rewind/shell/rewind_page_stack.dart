import "dart:math";

import "package:flutter/widgets.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_page_scope.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";

class RewindPageStack extends StatelessWidget {
  const RewindPageStack({
    required this.pages,
    required this.starts,
    required this.scroll,
    required this.navigator,
    this.reel = false,
    super.key,
  });

  final List<RewindPage> pages;
  final List<int> starts;
  final double scroll;
  final RewindNavigator navigator;
  final bool reel;

  static List<int> startsOf(List<RewindPage> pages) {
    final starts = <int>[];
    var step = 0;
    for (final page in pages) {
      starts.add(step);
      step += page.stops;
    }
    return starts;
  }

  @override
  Widget build(BuildContext context) {
    final activeStep = scroll.round();
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < pages.length; i++)
          if (scroll - starts[i] > -1 && scroll - starts[i] < pages[i].stops)
            _buildPage(
              pages[i],
              scroll - starts[i],
              isActive:
                  activeStep >= starts[i] &&
                  activeStep < starts[i] + pages[i].stops,
            ),
      ],
    );
  }

  Widget _buildPage(
    RewindPage page,
    double position, {
    required bool isActive,
  }) {
    final content = RewindPageScope(
      page: page,
      navigator: navigator,
      reel: reel,
      child: Builder(
        builder: (context) => page.build(context, position, isActive: isActive),
      ),
    );
    final entering = !page.pinned && position < 0;
    return ClipPath(
      key: ValueKey(page.key),
      clipper: _WaveClipper(entering ? 1 + position : 1),
      clipBehavior: entering ? Clip.antiAlias : Clip.none,
      child: content,
    );
  }
}

class _WaveClipper extends CustomClipper<Path> {
  _WaveClipper(this.progress);

  final double progress;

  @override
  Path getClip(Size size) {
    final scale = size.width / RewindStage.size.width;
    final amplitude = 16 * sin(pi * progress) * scale;
    final height = size.height;
    final base =
        height +
        amplitude +
        4 * scale -
        progress * (height + 2 * amplitude + 8 * scale);
    final path = Path()..moveTo(-10 * scale, height);
    for (var x = -10.0; x <= RewindStage.size.width + 10; x += 10) {
      path.lineTo(
        x * scale,
        base +
            amplitude * sin(x / RewindStage.size.width * 3 * pi + 5 * progress),
      );
    }
    return path
      ..lineTo((RewindStage.size.width + 10) * scale, height)
      ..close();
  }

  @override
  bool shouldReclip(_WaveClipper oldClipper) => oldClipper.progress != progress;
}
