import "package:flutter/material.dart";

class PhaseOffset extends Animatable<double> {
  const PhaseOffset(this.offset) : assert(offset >= 0 && offset < 1);

  final double offset;

  @override
  double transform(double t) => (t + offset) % 1.0;
}

class Horts extends StatefulWidget {
  const Horts({super.key});

  @override
  State<StatefulWidget> createState() => _HortsState();
}

const int _unit = 6400;

class _HortsState extends State<Horts> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4 * _unit),
    );
    _scaleAnimation = _controller.drive(
      TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.2), weight: 1),
        TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 1),
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.2), weight: 1),
        TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 1),
      ]),
    );
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final layers = _createLayers()
          ..sort((a, b) {
            final aProgress = (_controller.value + a.offset) % 1.0;
            final bProgress = (_controller.value + b.offset) % 1.0;
            return bProgress.compareTo(aProgress);
          });
        return Stack(
          children: [
            for (final layer in layers) Positioned.fill(child: layer),
            Positioned.fill(
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Image.asset("assets/horts0.png", scale: 2),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.72),
                  ],
                  stops: const [0.53663, 0.89955],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<_Hort> _createLayers() {
    const double n = 1 / 8;
    return [
      _Hort(_controller, "assets/horts1.png", n * 0),
      _Hort(_controller, "assets/horts2.png", n * 1),
      _Hort(_controller, "assets/horts3.png", n * 2),
      _Hort(_controller, "assets/horts4.png", n * 3),
      _Hort(_controller, "assets/horts1.png", n * 4),
      _Hort(_controller, "assets/horts2.png", n * 5),
      _Hort(_controller, "assets/horts3.png", n * 6),
      _Hort(_controller, "assets/horts4.png", n * 7),
    ];
  }
}

class _Hort extends StatefulWidget {
  final AnimationController controller;
  final String path;
  final double offset;

  _Hort(this.controller, this.path, this.offset) : super(key: ValueKey(offset));

  @override
  State<_Hort> createState() => _HortState();
}

class _HortState extends State<_Hort> with SingleTickerProviderStateMixin {
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleAnimation = widget.controller
        .drive(PhaseOffset(widget.offset))
        .drive(Tween<double>(begin: 0.0, end: 6.0));
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: Image.asset(widget.path),
    );
  }
}
