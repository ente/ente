import "dart:async";
import "dart:math";

import "package:flutter/material.dart";
import "package:flutter/scheduler.dart";
import "package:flutter/services.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/story/rewind_face.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_confetti.dart";
import "package:photos/ui/rewind/widgets/rewind_keyframes.dart";
import "package:photos/ui/rewind/widgets/rewind_numbers.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_swap_in.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

typedef RaceRunner = ({RewindFace face, rust.RacePerson person});

class PeopleRacePage extends RewindPage {
  PeopleRacePage(this.runners) : _start = _startOrder(runners);

  static const pageKey = "people_race";

  final List<RaceRunner> runners;
  final List<int> _start;
  int? _pick;

  @override
  String get key => pageKey;

  @override
  RewindChrome get chrome => const RewindChrome(foreground: RewindColors.cream);

  static List<int> _startOrder(List<RaceRunner> runners) {
    final seed = runners.map((runner) => runner.person.personId).join("|");
    return List.generate(runners.length, (i) => i)
      ..shuffle(Random(seed.hashCode));
  }

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    return _PeopleRace(page: this, position: position, isActive: isActive);
  }
}

enum _Phase { pick, picked, race, done }

class _Lane {
  _Lane(this.x, this.color);

  final Color color;
  double x;
  double from = 0;
  double goal = 0;
  double laneStartMs = 0;
  double count = 0;
  final trail = <({double world, double x, double y})>[];
}

class _PeopleRace extends StatefulWidget {
  const _PeopleRace({
    required this.page,
    required this.position,
    required this.isActive,
  });

  final PeopleRacePage page;
  final double position;
  final bool isActive;

  @override
  State<_PeopleRace> createState() => _PeopleRaceState();
}

class _PeopleRaceState extends State<_PeopleRace>
    with SingleTickerProviderStateMixin {
  static const _background = Color(0xFF9841E3);
  static const _stripes = Color(0xFF9D4EE0);
  static const _startLanes = [81.0, 195.0, 309.0];
  static const _rankLanes = [195.0, 81.0, 309.0];
  static const _colors = [
    Color(0xFF0B6CFB),
    Color(0xFFFF0A8E),
    Color(0xFFFFC40A),
  ];
  static const _base = 690.0;
  static const _rise = 330.0;
  static const _monthMs = 470.0;
  static const _rampMs = 350.0;
  static const _laneMs = 700.0;
  static const _speed = 0.75;
  static const _settleFrames = 36;

  late final Ticker _ticker = createTicker(_tick);
  late final List<_Lane> _lanes;
  late var _phase = _pick == null ? _Phase.pick : _Phase.done;
  late final _replayed = _phase == _Phase.done;
  late var _order = List.of(widget.page._start);
  late var _cue = _question;
  var _cueDetail = "Make a guess 👀";
  var _world = 0.0;
  var _speedFactor = 0.0;
  var _lastMs = 0.0;
  var _settling = 0;
  final _timers = <Timer>[];

  List<RaceRunner> get _runners => widget.page.runners;

  int? get _pick => widget.page._pick;

  static const _question = "WHO SHOWED UP MOST?";

  double get _top => _runners
      .map((runner) => runner.person.photoCount)
      .fold(1, (a, b) => max(a, b))
      .toDouble();

  double _headY(double count) => _base - _rise * count / _top;

  @override
  void initState() {
    super.initState();
    _lanes = List.generate(_runners.length, (i) {
      final start = widget.page._start.indexOf(i);
      return _Lane(_startLanes[start], _colors[start]);
    });
    if (_phase == _Phase.done) _finishInstantly();
  }

  @override
  void dispose() {
    _ticker.dispose();
    for (final timer in _timers) {
      timer.cancel();
    }
    super.dispose();
  }

  void _later(Duration delay, VoidCallback callback) {
    _timers.add(
      Timer(delay, () {
        if (mounted) callback();
      }),
    );
  }

  void _choose(int runner) {
    if (_phase != _Phase.pick) return;
    unawaited(HapticFeedback.selectionClick());
    widget.page._pick = runner;
    setState(() {
      _phase = _Phase.picked;
      _cueDetail = "${_runners[runner].face.name}? bold choice";
    });
    _later(const Duration(milliseconds: 850), () {
      setState(() => _phase = _Phase.race);
      unawaited(_ticker.start());
    });
  }

  void _tick(Duration elapsed) {
    final nowMs = elapsed.inMicroseconds / 1000;
    final dt = _lastMs == 0 ? 16.0 : min(50.0, nowMs - _lastMs);
    _lastMs = nowMs;
    const raceMs = 12 * _monthMs;
    if (_settling == 0) {
      _speedFactor = min(1, nowMs / _rampMs);
    } else {
      _speedFactor *= 0.86;
    }
    _world += dt * _speedFactor;
    for (final lane in _lanes) {
      lane.trail.add((world: _world, x: lane.x, y: _headY(lane.count)));
      while (lane.trail.isNotEmpty &&
          (_world - lane.trail.first.world) * _speed > 1300) {
        lane.trail.removeAt(0);
      }
    }
    final t = min(1.0, nowMs / raceMs);
    final months = t * 12;
    final month = min(11, months.floor());
    for (final (i, runner) in _runners.indexed) {
      final counts = runner.person.monthlyCounts;
      final from = month == 0 ? 0 : counts[month - 1];
      _lanes[i].count = t >= 1
          ? counts[11].toDouble()
          : from + (counts[month] - from) * (months - months.floor());
    }
    final ranked = _ranked();
    if (t > 0.03 && !_sameOrder(ranked)) {
      final passer = ranked.firstWhere(
        (runner) => _order.indexOf(runner) > ranked.indexOf(runner),
        orElse: () => -1,
      );
      if (passer >= 0 && month > 0) {
        final passed = _order[ranked.indexOf(passer)];
        _cue =
            "${_nameOf(passer).toUpperCase()} OVERTAKES "
            "${_nameOf(passed).toUpperCase()}!";
        _cueDetail = "";
        unawaited(HapticFeedback.selectionClick());
      }
      _order = ranked;
    }
    for (final (rank, runner) in _order.indexed) {
      _steer(_lanes[runner], _rankLanes[rank], nowMs);
    }
    if (t >= 1 && ++_settling >= _settleFrames) {
      _ticker.stop();
      _finish();
    }
    setState(() {});
  }

  void _steer(_Lane lane, double target, double nowMs) {
    if (target != lane.goal) {
      lane
        ..from = lane.x
        ..goal = target
        ..laneStartMs = nowMs;
    }
    final p = min(1.0, (nowMs - lane.laneStartMs) / _laneMs);
    lane.x =
        lane.from +
        (lane.goal - lane.from) * Curves.easeInOutCubic.transform(p);
  }

  List<int> _ranked() {
    final runners = List.generate(_runners.length, (i) => i);
    return runners..sort((a, b) {
      final byCount = _lanes[b].count.compareTo(_lanes[a].count);
      return byCount != 0 ? byCount : a - b;
    });
  }

  bool _sameOrder(List<int> ranked) {
    for (var i = 0; i < ranked.length; i++) {
      if (ranked[i] != _order[i]) return false;
    }
    return true;
  }

  String _nameOf(int runner) => _runners[runner].face.name ?? "";

  void _finish() {
    _phase = _Phase.done;
    _cue = _verdict;
    _cueDetail = "";
    unawaited(
      _pick == 0 ? HapticFeedback.mediumImpact() : HapticFeedback.lightImpact(),
    );
  }

  void _finishInstantly() {
    for (final (i, runner) in _runners.indexed) {
      _lanes[i].count = runner.person.photoCount.toDouble();
    }
    _order = List.generate(_runners.length, (i) => i);
    for (final (rank, runner) in _order.indexed) {
      _lanes[runner].x = _rankLanes[rank];
    }
    _cue = _verdict;
    _cueDetail = "";
  }

  String get _verdict => switch (_pick) {
    0 => "YOU CALLED IT!",
    1 => "SO CLOSE!",
    _ => "NOT THIS YEAR!",
  };

  @override
  Widget build(BuildContext context) {
    final racing = _phase == _Phase.race || _phase == _Phase.done;
    return RewindShareable(
      enabled: _phase == _Phase.done,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _phase == _Phase.done ? null : () {},
        child: Stack(
          fit: StackFit.expand,
          children: [
            const RewindBackdrop(
              color: _background,
              pattern: RewindStripes(_stripes),
            ),
            MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: _replayed),
              child: RewindStage(
                children: [
                  Positioned.fill(
                    child: RewindLeave(
                      position: widget.position,
                      centerY: 620,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: AnimatedOpacity(
                              opacity: racing ? 1 : 0,
                              duration: const Duration(milliseconds: 400),
                              child: CustomPaint(
                                painter: _StreaksPainter(
                                  _world * _speed * 1.25,
                                ),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _PillarsPainter(_pillars()),
                            ),
                          ),
                          for (final runner in _paintOrder()) _column(runner),
                        ],
                      ),
                    ),
                  ),
                  if (_phase == _Phase.done && !_replayed)
                    Positioned.fill(
                      child: RewindConfetti(
                        count: _pick == 0 ? 80 : 30,
                        active: true,
                      ),
                    ),
                  Positioned(
                    left: 10,
                    right: 10,
                    top: 160,
                    child: RewindLeave(
                      position: widget.position,
                      centerY: 180,
                      child: _cues(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cues() {
    return Column(
      children: [
        RewindSwapIn(
          text: _cue,
          child: RewindFitWidth(
            width: 370,
            alignment: Alignment.center,
            child: Text(
              _cue,
              textAlign: TextAlign.center,
              style: RewindTextStyles.display(
                20,
                color: RewindColors.white,
                height: 1.1,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
        const SizedBox(height: 7),
        RewindSwapIn(
          text: _cueDetail,
          child: RewindFitWidth(
            width: 370,
            alignment: Alignment.center,
            child: Text(
              _cueDetail,
              textAlign: TextAlign.center,
              style: RewindTextStyles.body(17, height: 1.2),
            ),
          ),
        ),
      ],
    );
  }

  List<int> _paintOrder() {
    final leader = _order.first;
    return [
      for (final runner in _order.reversed)
        if (runner != leader) runner,
      leader,
    ];
  }

  List<({Path path, Color color})> _pillars() {
    return [
      for (final runner in _paintOrder())
        (
          path: _pillarPath(_lanes[runner]),
          color: _dimmed(runner)
              ? _tinted(_lanes[runner].color, _Face._dimMatrix)
              : _lanes[runner].color,
        ),
    ];
  }

  bool _dimmed(int runner) => _phase == _Phase.picked && _pick != runner;

  Path _pillarPath(_Lane lane) {
    const body = 38.0;
    final head = _headY(lane.count);
    final points = <Offset>[Offset(lane.x, head + body)];
    for (var i = lane.trail.length - 1; i >= 0; i--) {
      final sample = lane.trail[i];
      final y = sample.y + body + (_world - sample.world) * _speed;
      if (y - points.last.dy < 4 && i > 0) continue;
      points.add(Offset(sample.x, y));
      if (y > 904) break;
    }
    if (points.last.dy < 904) points.add(Offset(points.last.dx, 904));
    return _outline(_smooth(points));
  }

  Widget _column(int runner) {
    final lane = _lanes[runner];
    final face = _runners[runner].face;
    final head = _headY(lane.count);
    final rank = _order.indexOf(runner);
    final winner = _phase == _Phase.done && rank == 0;
    final countTop = winner ? -55.0 : -40.0;
    final picked = _pick == runner;
    return Positioned(
      left: lane.x - 51.5,
      top: head - 45,
      width: 103,
      height: max(140, 860 - head),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _phase == _Phase.pick ? () => _choose(runner) : null,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 2.5,
              top: -4,
              width: 98,
              height: 98,
              child: _Face(face: face, dimmed: _dimmed(runner)),
            ),
            Positioned(
              left: -40,
              right: -40,
              top: countTop,
              child: AnimatedOpacity(
                opacity: _phase == _Phase.pick ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: Center(
                  child: RewindOutlinedText(
                    rewindCount(lane.count.round()),
                    style: RewindTextStyles.display(27),
                    outline: 2.4,
                    shadow: const Offset(1.5, 2),
                  ),
                ),
              ),
            ),
            Positioned(
              left: -40,
              right: -40,
              top: countTop - 34,
              child: Center(
                child: AnimatedScale(
                  scale: picked ? 1 : 0,
                  duration: const Duration(milliseconds: 350),
                  curve: const Cubic(0.2, 0.9, 0.3, 1.4),
                  child: Transform.rotate(
                    angle: -5 * pi / 180,
                    child: const _PickTag(),
                  ),
                ),
              ),
            ),
            Positioned(
              left: -20,
              right: -20,
              top: 98,
              child: Center(
                child: AnimatedScale(
                  scale: _phase == _Phase.race || _phase == _Phase.done ? 1 : 0,
                  duration: const Duration(milliseconds: 350),
                  curve: const Cubic(0.2, 0.9, 0.3, 1.4),
                  child: RewindOutlinedText(
                    "${rank + 1}",
                    style: RewindTextStyles.display(
                      60,
                      color: RewindColors.white,
                      height: 1,
                    ),
                    outline: 4,
                    shadow: const Offset(3, 4),
                  ),
                ),
              ),
            ),
            if (winner)
              Positioned.fromRect(
                rect: Rect.fromCenter(
                  center: const Offset(51.5 + 34.5, 45 - 47.7),
                  width: 51.9,
                  height: 41.19,
                ),
                child: RewindKeyframes(
                  active: true,
                  durationMs: 600,
                  curve: const Cubic(0.2, 0.9, 0.3, 1.4),
                  poses: const [
                    RewindPose(0, dy: -60, scale: 0.3, turn: -30, opacity: 0),
                    RewindPose(0.55, dy: 4, scale: 1.27, turn: 4),
                    RewindPose(1, turn: 27.6),
                  ],
                  child: SvgPicture.file(RewindAssets.file(RewindAssets.crown)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static List<Offset> _smooth(List<Offset> points) {
    if (points.length < 2) return points;
    const steps = 4;
    final smooth = <Offset>[];
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[max(0, i - 1)];
      final p1 = points[i];
      final p2 = points[i + 1];
      final p3 = points[min(points.length - 1, i + 2)];
      for (var k = 0; k < steps; k++) {
        final t = k / steps;
        final t2 = t * t;
        final t3 = t2 * t;
        smooth.add(
          (p1 * 2 +
                  (-p0 + p2) * t +
                  (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 +
                  (-p0 + p1 * 3 - p2 * 3 + p3) * t3) *
              0.5,
        );
      }
    }
    return smooth..add(points.last);
  }

  static Path _outline(List<Offset> points) {
    const half = 49.75;
    const corner = 26.0;
    Offset tangentAt(int i) {
      final delta =
          points[min(points.length - 1, i + 1)] - points[max(0, i - 1)];
      final length = delta.distance;
      return length == 0 ? const Offset(0, 1) : delta / length;
    }

    final top = points.first;
    final down = tangentAt(0);
    final across = Offset(-down.dy, down.dx);
    Offset local(double x, double y) => top + across * x + down * y;
    final right = <Offset>[];
    final left = <Offset>[];
    var distance = 0.0;
    for (var i = 0; i < points.length; i++) {
      if (i > 0) distance += (points[i] - points[i - 1]).distance;
      if (distance < corner) continue;
      final tangent = tangentAt(i);
      final normal = Offset(-tangent.dy, tangent.dx);
      right.add(points[i] - normal * half);
      left.add(points[i] + normal * half);
    }
    final cap = [
      for (var k = 0; k <= 6; k++)
        local(
          -half + corner + corner * cos(pi + pi / 2 * k / 6),
          corner + corner * sin(pi + pi / 2 * k / 6),
        ),
      for (var k = 0; k <= 6; k++)
        local(
          half - corner + corner * cos(-pi / 2 + pi / 2 * k / 6),
          corner + corner * sin(-pi / 2 + pi / 2 * k / 6),
        ),
    ];
    return Path()..addPolygon([...right.reversed, ...cap, ...left], true);
  }
}

class _Face extends StatelessWidget {
  const _Face({required this.face, required this.dimmed});

  final RewindFace face;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final crop = face.crop;
    final name = face.name ?? "";
    final image = crop == null
        ? ColoredBox(
            color: RewindColors.ink,
            child: Center(
              child: Text(
                name.isEmpty ? "?" : name.characters.first.toUpperCase(),
                style: RewindTextStyles.display(40),
              ),
            ),
          )
        : Image.memory(crop, fit: BoxFit.cover, gaplessPlayback: true);
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: RewindColors.cream,
        shape: BoxShape.circle,
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: ClipOval(
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix(
              dimmed ? _dimMatrix : _identityMatrix,
            ),
            child: image,
          ),
        ),
      ),
    );
  }

  static final _identityMatrix = _tint(saturation: 1, brightness: 1);
  static final _dimMatrix = _tint(saturation: 0.55, brightness: 0.92);
}

List<double> _tint({required double saturation, required double brightness}) {
  const luma = [0.2126, 0.7152, 0.0722];
  return [
    for (var row = 0; row < 3; row++) ...[
      for (var column = 0; column < 3; column++)
        (luma[column] * (1 - saturation) + (row == column ? saturation : 0)) *
            brightness,
      0,
      0,
    ],
    0,
    0,
    0,
    1,
    0,
  ];
}

Color _tinted(Color color, List<double> matrix) {
  final channels = [color.r, color.g, color.b];
  double channel(int row) => [
    for (var column = 0; column < 3; column++)
      matrix[row * 5 + column] * channels[column],
  ].reduce((a, b) => a + b).clamp(0.0, 1.0);
  return Color.from(
    alpha: color.a,
    red: channel(0),
    green: channel(1),
    blue: channel(2),
  );
}

class _PickTag extends StatelessWidget {
  const _PickTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 5),
      decoration: BoxDecoration(
        color: RewindColors.ink,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        "YOUR PICK",
        style: RewindTextStyles.display(13, height: 1, letterSpacing: 0.3),
      ),
    );
  }
}

class _PillarsPainter extends CustomPainter {
  _PillarsPainter(this.pillars);

  final List<({Path path, Color color})> pillars;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeJoin = StrokeJoin.round
      ..color = RewindColors.cream;
    for (final pillar in pillars) {
      canvas.drawPath(pillar.path, Paint()..color = pillar.color);
      canvas.drawPath(pillar.path, outline);
    }
  }

  @override
  bool shouldRepaint(_PillarsPainter oldDelegate) => true;
}

class _StreaksPainter extends CustomPainter {
  _StreaksPainter(this.travel);

  static const _streaks = [
    (x: 175.9, length: 80.7, y: 702.1),
    (x: 27.0, length: 32.9, y: 748.1),
    (x: 16.7, length: 34.6, y: 692.7),
    (x: 177.9, length: 42.5, y: 748.1),
    (x: 182.7, length: 51.4, y: 812.9),
    (x: 254.1, length: 64.2, y: 153.6),
    (x: 340.9, length: 77.6, y: 383.8),
    (x: 139.5, length: 99.7, y: 743.2),
    (x: 102.7, length: 38.2, y: 686.6),
    (x: 192.2, length: 46.0, y: 731.1),
    (x: 180.2, length: 99.5, y: 604.3),
    (x: 153.1, length: 31.5, y: 850.1),
    (x: 330.2, length: 62.3, y: 783.1),
    (x: 266.7, length: 71.8, y: 703.7),
    (x: 166.4, length: 77.1, y: 663.0),
    (x: 175.6, length: 82.1, y: 141.3),
  ];

  final double travel;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = RewindColors.cream.withValues(alpha: 0.22)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final streak in _streaks) {
      final y = (streak.y + 80 + travel) % 1000 - 80;
      canvas.drawLine(
        Offset(streak.x, y),
        Offset(streak.x, y + streak.length),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StreaksPainter oldDelegate) =>
      oldDelegate.travel != travel;
}
