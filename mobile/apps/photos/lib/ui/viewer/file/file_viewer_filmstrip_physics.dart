import "package:flutter/widgets.dart";

const ScrollPhysics fileViewerFilmstripPhysics = _FilmstripScrollPhysics();

const _maxFlingVelocity = 800.0;
// Evaluating a slightly faster clamping simulation on a slower clock keeps the
// launch velocity unchanged while extending its distance and settling time.
const _ballisticTimeScale = 0.7;

// Use the same deceleration on every platform, including iOS.
class _FilmstripScrollPhysics extends ClampingScrollPhysics {
  const _FilmstripScrollPhysics({super.parent});

  @override
  _FilmstripScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _FilmstripScrollPhysics(parent: buildParent(ancestor));

  @override
  double get maxFlingVelocity => _maxFlingVelocity;

  @override
  double carriedMomentum(double existingVelocity) {
    // Preserve repeated-fling acceleration with a cap on the added momentum.
    final momentum = const BouncingScrollPhysics().carriedMomentum(
      existingVelocity,
    );
    return momentum.clamp(-_maxFlingVelocity, _maxFlingVelocity).toDouble();
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final cappedVelocity = velocity
        .clamp(-_maxFlingVelocity, _maxFlingVelocity)
        .toDouble();
    if (position.outOfRange ||
        cappedVelocity.abs() < toleranceFor(position).velocity) {
      return super.createBallisticSimulation(position, cappedVelocity);
    }
    final simulation = super.createBallisticSimulation(
      position,
      cappedVelocity / _ballisticTimeScale,
    );
    return simulation == null
        ? null
        : _FilmstripBallisticSimulation(
            simulation,
            timeScale: _ballisticTimeScale,
          );
  }
}

class _FilmstripBallisticSimulation extends Simulation {
  final Simulation _simulation;
  final double _timeScale;

  _FilmstripBallisticSimulation(this._simulation, {required double timeScale})
    : assert(timeScale > 0 && timeScale <= 1),
      _timeScale = timeScale,
      super(tolerance: _simulation.tolerance);

  @override
  double x(double time) => _simulation.x(time * _timeScale);

  @override
  double dx(double time) => _simulation.dx(time * _timeScale) * _timeScale;

  @override
  bool isDone(double time) => _simulation.isDone(time * _timeScale);
}
