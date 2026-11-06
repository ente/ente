import "dart:math";

import "package:flutter/animation.dart";

class RewindSpring extends Curve {
  const RewindSpring(this.stiffness, this.damping, this.duration);

  final double stiffness;
  final double damping;
  final Duration duration;

  @override
  double transformInternal(double t) {
    final seconds =
        t * duration.inMicroseconds / Duration.microsecondsPerSecond;
    final omega = sqrt(stiffness);
    final zeta = damping / (2 * omega);
    final decay = zeta * omega;
    final damped = omega * sqrt(1 - zeta * zeta);
    return 1 -
        exp(-decay * seconds) *
            (cos(damped * seconds) + decay / damped * sin(damped * seconds));
  }
}

abstract final class RewindMotion {
  static const expo = Cubic(0.16, 1, 0.3, 1);
  static const wave = Cubic(0.65, 0, 0.25, 1);
  static const hop = Cubic(0.25, 0.8, 0.3, 1);
  static const squash = Cubic(0.22, 0.9, 0.3, 1);
  static const sway = Cubic(0.33, 0, 0.67, 1);
  static const bloom = Cubic(0.3, 0, 0.2, 1);
  static const railBounce = Cubic(0.3, 1.5, 0.5, 1);

  static const pop = RewindSpring(330, 15, Duration(milliseconds: 879));
  static const soft = RewindSpring(170, 17, Duration(milliseconds: 792));
  static const slap = RewindSpring(420, 21, Duration(milliseconds: 642));
  static const drop = RewindSpring(230, 16, Duration(milliseconds: 833));
  static const bubble = RewindSpring(260, 13, Duration(milliseconds: 992));

  static const waveDuration = Duration(milliseconds: 900);
}
