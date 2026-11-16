import "dart:math";
import "dart:typed_data";
import "dart:ui" as ui;

import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter/scheduler.dart";
import "package:flutter/services.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_page_scope.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_hint.dart";
import "package:photos/ui/rewind/widgets/rewind_numbers.dart";
import "package:photos/ui/rewind/widgets/rewind_photo_frames.dart";
import "package:photos/ui/rewind/widgets/rewind_pixels.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

const _months = [
  "JAN",
  "FEB",
  "MAR",
  "APR",
  "MAY",
  "JUN",
  "JUL",
  "AUG",
  "SEP",
  "OCT",
  "NOV",
  "DEC",
];

const _monthNames = [
  "JANUARY",
  "FEBRUARY",
  "MARCH",
  "APRIL",
  "MAY",
  "JUNE",
  "JULY",
  "AUGUST",
  "SEPTEMBER",
  "OCTOBER",
  "NOVEMBER",
  "DECEMBER",
];

const _weekdays = [
  "MONDAY",
  "TUESDAY",
  "WEDNESDAY",
  "THURSDAY",
  "FRIDAY",
  "SATURDAY",
  "SUNDAY",
];

class WarpPage extends RewindPage {
  WarpPage({
    required this.photos,
    required this.first,
    this.bytes = rewindThumbnailBytes,
    this.photo = rewindPhoto,
  });

  static const pageKey = "warp";
  static const minimumPanels = 48;

  final List<EnteFile> photos;
  final EnteFile first;
  final RewindBytes bytes;
  final RewindPhotoBuilder photo;

  late final RewindWarm<RewindAtlas> _walls = RewindWarm(
    () => RewindAtlas.load(
      photos,
      tile: 96,
      bytes: bytes,
      minimum: minimumPanels,
    ),
    (atlas) => atlas.dispose(),
  );

  late final RewindWarm<RewindDecoded> _landing = RewindDecoded.warm([
    first,
  ], bytes);

  static final _wallClock = RegExp(r"^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}");

  static DateTime taken(EnteFile file) =>
      DateTime.tryParse(
        _wallClock.stringMatch(file.pubMagicMetadata?.dateTime ?? "") ?? "",
      ) ??
      _instant(file);

  static DateTime _instant(EnteFile file) =>
      DateTime.fromMicrosecondsSinceEpoch(file.creationTime ?? 0);

  static String dated(DateTime day) =>
      "${day.day} ${_months[day.month - 1]} ${day.year}";

  @override
  String get key => pageKey;

  @override
  Duration? get reelHold => const Duration(milliseconds: 4000);

  @override
  List<EnteFile> get reelThumbnails => [first];

  @override
  Future<bool> warmUp() async {
    final landing = _landing.value;
    final walls = await _walls.value;
    await landing;
    return walls != null;
  }

  @override
  void release() {
    _walls.release();
    _landing.release();
  }

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    return RewindWarmBuilder<RewindAtlas>(
      warm: _walls,
      builder: (context, walls) => RewindWarmBuilder<RewindDecoded>(
        warm: _landing,
        builder: (context, landing) => _Flight(
          key: ValueKey(walls),
          walls: walls,
          first: first,
          landing: landing,
          photo: photo,
          active: isActive,
          position: position,
        ),
      ),
    );
  }
}

class _Flight extends StatefulWidget {
  const _Flight({
    required this.walls,
    required this.first,
    required this.landing,
    required this.photo,
    required this.active,
    required this.position,
    super.key,
  });

  final RewindAtlas? walls;
  final EnteFile first;
  final RewindDecoded? landing;
  final RewindPhotoBuilder photo;
  final bool active;
  final double position;

  @override
  State<_Flight> createState() => _FlightState();
}

class _FlightState extends State<_Flight> with TickerProviderStateMixin {
  static const _printWidth = 228.0;
  static const _coastMs = 380.0;
  static const _seekMs = 170.0;
  static const _wheelSpan = 900.0;
  static const _rollSpan = 140.0;
  static const _rollCoastMs = 520.0;
  static const _detent = pi / 3;
  static const _holdFor = Duration(milliseconds: 250);
  static const _holdSlop = 12.0;
  static const _brakeMs = 90.0;
  static const _hintFromMs = 1500.0;
  static const _hintMs = 2200.0;
  static const _pickedAt = Offset(195, 356);

  late final _reel = RewindPageScope.reelOf(context);
  late final _flightMs = _reel ? 2800.0 : 9500.0;
  late final _countdownMs = _reel ? 300.0 : 900.0;
  late final Ticker _ticker = createTicker(_onTick);
  late final AnimationController _pull = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    reverseDuration: const Duration(milliseconds: 220),
  )..addStatusListener(_onPull);
  late final _Course _course = _Course(
    (widget.walls?.length ?? 0) ~/ _Course.sides,
  );
  late final List<_Month> _calendar = _Month.along(_course, widget.walls);

  var _last = Duration.zero;
  var _ms = 0.0;
  var _flownMs = 0.0;
  var _guidedMs = 0.0;
  var _travelled = 0.0;
  var _previous = 0.0;
  var _velocity = 0.0;
  var _pace = 0.0;
  var _piloted = false;
  var _still = false;
  var _dragging = false;
  var _roll = 0.0;
  var _rollRate = 0.0;
  var _rollSide = 1.0;
  var _rolling = false;
  var _hasRolled = false;
  var _detents = 0;
  var _held = false;
  var _hasHeld = false;
  var _heldBy = Offset.zero;
  Axis? _heldAxis;
  var _brake = 0.0;
  double? _seek;
  double? _landedMs;
  var _gate = -1;
  int? _picked;
  var _pickedFrom = _Course.vanish;
  var _hasPicked = false;

  bool get _landed =>
      widget.walls != null && _travelled >= _course.length - 0.01;

  bool get _canHold =>
      _held ||
      (!_piloted && !_landed) ||
      _velocity != 0 ||
      _seek != null ||
      _rollRate != 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Flight oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _pull.dispose();
    super.dispose();
  }

  void _sync() {
    _still = MediaQuery.disableAnimationsOf(context);
    if (_still && !_piloted) {
      _travelled = _course.length;
      _landedMs ??= _ms - 10000;
    }
    if (widget.active && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!widget.active && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1000;
    _last = elapsed;
    if (dt <= 0) return;
    _ms += dt;
    _brake += ((_held ? 1 : 0) - _brake) * (1 - exp(-dt / _brakeMs));
    if (widget.walls != null && _picked == null) _fly(dt);
    _coastRoll(dt);
    final rate = (_travelled - _previous).abs() / dt;
    _previous = _travelled;
    final cruise = 2 * _course.length / _flightMs;
    _pace += ((rate / cruise).clamp(0.0, 1.0) - _pace) * (1 - exp(-dt / 160));
    if (_landed) {
      if (_landedMs == null) {
        _landedMs = _ms;
        if (!_reel) HapticFeedback.mediumImpact();
      }
    } else {
      _landedMs = null;
    }
    final month = _passing?.month;
    if (month != null && month != _gate) {
      if (_gate != -1 && !_landed && !_reel) HapticFeedback.selectionClick();
      _gate = month;
    }
    setState(() {});
  }

  void _fly(double dt) {
    final length = _course.length;
    if (!_piloted) {
      _guidedMs += dt;
      _flownMs += dt * (1 - _brake);
      _travelled = _still
          ? length
          : length *
                Curves.easeInOutCubic.transform(
                  ((_flownMs - _countdownMs) / _flightMs).clamp(0.0, 1.0),
                );
      return;
    }
    final step = min(dt, 50.0);
    final seek = _seek;
    if (seek != null) {
      _travelled += (seek - _travelled) * (1 - exp(-step / _seekMs));
      if ((seek - _travelled).abs() < 0.01) _seek = null;
    } else if (!_dragging && _velocity != 0) {
      _travelled = (_travelled + _velocity * step).clamp(0.0, length);
      _velocity *= exp(-step / _coastMs);
      if (_velocity.abs() < 0.0003 || _travelled <= 0 || _travelled >= length) {
        _velocity = 0;
      }
    }
  }

  void _coastRoll(double dt) {
    if (!_rolling && _rollRate != 0) {
      final step = min(dt, 50.0);
      _roll += _rollRate * step;
      _rollRate *= exp(-step / _rollCoastMs);
      if (_rollRate.abs() < 0.00008) _rollRate = 0;
    }
    final detents = (_roll / _detent).round();
    if (detents == _detents) return;
    _detents = detents;
    HapticFeedback.selectionClick();
  }

  DateTime? get _passing {
    final walls = widget.walls;
    if (walls == null) return null;
    final ring = min(
      max(0, _course.rings - 1),
      max(0, ((_travelled - _Course.lead) / _Course.gap).floor()),
    );
    return WarpPage.taken(walls.files[ring * _Course.sides]);
  }

  void _takeOver() {
    _release();
    _piloted = true;
    _dragging = true;
    _velocity = 0;
    _seek = null;
  }

  void _steer(double dx, double span) => _travelled =
      (_travelled - dx / span * _course.length).clamp(0.0, _course.length);

  void _letGo(double pixelsPerSecond, double span) {
    _dragging = false;
    _velocity = -pixelsPerSecond / span * _course.length / 1000;
  }

  double _sideOf(double x) => x < _Course.vanish.dx ? -1 : 1;

  void _startRoll(double x) {
    _release();
    _rolling = true;
    _rollRate = 0;
    _rollSide = _sideOf(x);
  }

  void _rollBy(double dy) {
    _roll += _rollSide * dy / _rollSpan;
    _hasRolled = true;
  }

  void _endRoll(double pixelsPerSecond) {
    _rolling = false;
    _rollRate = _still ? 0 : _rollSide * pixelsPerSecond / _rollSpan / 1000;
  }

  void _listenForHold(LongPressGestureRecognizer recognizer) {
    recognizer.onLongPressStart = (details) => _hold(details.localPosition.dx);
    recognizer.onLongPressMoveUpdate = (details) =>
        _holdMove(details.localOffsetFromOrigin);
    recognizer.onLongPressEnd = (details) =>
        _letHoldGo(details.velocity.pixelsPerSecond);
    recognizer.onLongPressCancel = () => _letHoldGo(Offset.zero);
  }

  void _hold(double x) {
    _release();
    _held = true;
    _hasHeld = true;
    _heldBy = Offset.zero;
    _heldAxis = null;
    _velocity = 0;
    _seek = null;
    _rollRate = 0;
    _rollSide = _sideOf(x);
    HapticFeedback.selectionClick();
  }

  void _holdMove(Offset moved) {
    final delta = moved - _heldBy;
    _heldBy = moved;
    switch (_heldAxis) {
      case Axis.horizontal:
        _steer(delta.dx, _wheelSpan);
      case Axis.vertical:
        _rollBy(delta.dy);
      case null:
        if (moved.distance < _holdSlop) return;
        if (moved.dx.abs() > moved.dy.abs()) {
          _heldAxis = Axis.horizontal;
          _takeOver();
        } else {
          _heldAxis = Axis.vertical;
          _rolling = true;
        }
    }
  }

  void _letHoldGo(Offset pixelsPerSecond) {
    if (!_held) return;
    _held = false;
    switch (_heldAxis) {
      case Axis.horizontal:
        _letGo(pixelsPerSecond.dx, _wheelSpan);
      case Axis.vertical:
        _endRoll(pixelsPerSecond.dy);
      case null:
    }
  }

  void _jump(double x) {
    _release();
    _piloted = true;
    _velocity = 0;
    _seek =
        _course.length *
        ((_Rail.span - (x - _Rail.inset)) / _Rail.span).clamp(0.0, 1.0);
  }

  void _flyAgain() {
    _release();
    _piloted = false;
    _flownMs = 0;
    _guidedMs = 0;
    _velocity = 0;
    _seek = null;
    _gate = -1;
  }

  void _release() {
    if (_picked != null) _pull.reverse();
  }

  void _onPull(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) setState(() => _picked = null);
  }

  void _tap(Offset at) {
    if (_picked != null) {
      _release();
      return;
    }
    final onFirst =
        _landed &&
        Rect.fromCenter(
          center: _Course.vanish,
          width: _printWidth,
          height: _printWidth * 1.22,
        ).contains(at);
    final panel = onFirst ? null : _course.panelAt(at, _travelled, _roll);
    if (panel == null) {
      final navigator = RewindPageScope.navigatorOf(context);
      at.dx < RewindStage.size.width / 3
          ? navigator?.previous()
          : navigator?.next();
      return;
    }
    HapticFeedback.lightImpact();
    _velocity = 0;
    _rollRate = 0;
    _seek = null;
    _piloted = true;
    _hasPicked = true;
    _pickedFrom = at;
    _picked = panel;
    _pull.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final walls = widget.walls;
    final course = _course;
    final travelled = _travelled;
    final landed = _landed;
    final sinceLanding = landed ? _ms - (_landedMs ?? _ms) : -1.0;
    final passing = _passing;
    final ahead = course.end - travelled;
    final arrival =
        ((_Course.sighted - ahead) / (_Course.sighted - _Course.landing)).clamp(
          0.0,
          1.0,
        );
    final door = course.project(course.end, travelled, 0, 0);
    final settle = Curves.easeOutBack.transform(
      (sinceLanding / 420).clamp(0.0, 1.0),
    );
    final picked = _picked;
    final pulled = Curves.easeOutCubic.transform(_pull.value);
    final canPick = walls != null && (_piloted || landed);
    final hint = _hint(landed, sinceLanding, canPick);
    return Stack(
      fit: StackFit.expand,
      children: [
        RewindShareable(
          enabled: walls != null && widget.landing != null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Color(0xFF120E2E)),
              RewindStage(
                children: [
                  Positioned.fill(
                    child: RewindLeave(
                      position: widget.position,
                      centerY: 400,
                      child: CustomPaint(
                        painter: _Tube(
                          walls: walls,
                          course: course,
                          travelled: travelled,
                          roll: _roll,
                          speed: _pace,
                          arrival: arrival,
                          sinceLanding: sinceLanding,
                          dim: pulled,
                          ms: _ms,
                        ),
                      ),
                    ),
                  ),
                  if (walls != null)
                    Positioned(
                      left: door.dx - 160,
                      top: door.dy - 180,
                      width: 320,
                      height: 360,
                      child: RewindLeave(
                        position: widget.position,
                        centerY: 400,
                        child: IgnorePointer(
                          child: Center(
                            child: Opacity(
                              opacity:
                                  (arrival * 5).clamp(0.0, 1.0) * (1 - pulled),
                              child: Transform.rotate(
                                angle: -0.06 * settle,
                                child: Transform.scale(
                                  scale:
                                      _Course.landing /
                                      ahead *
                                      (0.94 + 0.06 * settle),
                                  child: _Print(
                                    width: _printWidth,
                                    photo: widget.photo(
                                      widget.first,
                                      decoded: widget.landing?[widget.first],
                                    ),
                                    caption: WarpPage.dated(
                                      WarpPage.taken(widget.first),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (walls != null && picked != null)
                    Positioned(
                      left: _pickedAt.dx - 160,
                      top: _pickedAt.dy - 180,
                      width: 320,
                      height: 360,
                      child: RewindLeave(
                        position: widget.position,
                        centerY: 400,
                        child: IgnorePointer(
                          child: Center(
                            child: Opacity(
                              opacity: (pulled * 3).clamp(0.0, 1.0),
                              child: Transform.translate(
                                offset:
                                    (_pickedFrom - _pickedAt) * (1 - pulled),
                                child: Transform.rotate(
                                  angle:
                                      (picked.isEven ? 1 : -1) *
                                      (0.05 + 0.5 * (1 - pulled)),
                                  child: Transform.scale(
                                    scale: 0.14 + 0.86 * pulled,
                                    child: _Print(
                                      width: _printWidth,
                                      photo: widget.photo(walls.files[picked]),
                                      caption: WarpPage.dated(
                                        WarpPage.taken(walls.files[picked]),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 96,
                    child: RewindLeave(
                      position: widget.position,
                      centerY: 120,
                      child: Opacity(
                        opacity: 1 - pulled,
                        child: Center(
                          child: RewindVoice(
                            you: "YOU MADE IT BACK",
                            me: "I MADE IT BACK",
                            builder: (madeIt) => _Counter(
                              landed
                                  ? madeIt
                                  : walls == null
                                  ? "LOADING THE TAPE"
                                  : _piloted
                                  ? "TIME TRAVEL"
                                  : _held
                                  ? "PAUSED"
                                  : "REWINDING",
                              passing == null || landed
                                  ? null
                                  : "${passing.day} ${_months[passing.month - 1]}",
                              paused: _held && !_piloted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 28,
                    top: 606,
                    width: 334,
                    child: RewindLeave(
                      position: widget.position,
                      centerY: 660,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 380),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeIn,
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.topLeft,
                          children: [...previous, ?current],
                        ),
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween(
                              begin: const Offset(0, 0.12),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        child: walls != null && picked != null
                            ? _caption(walls.files[picked])
                            : landed
                            ? _Caption(
                                key: const ValueKey("first"),
                                eyebrow: _ago,
                                title: "IT STARTED HERE",
                                body:
                                    "Your first photo of the year. Look how "
                                    "far you have come since.",
                                myBody:
                                    "My first photo of the year. Look how "
                                    "far I have come since.",
                              )
                            : const SizedBox(
                                key: ValueKey("flying"),
                                width: 334,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        RewindStage(
          children: [
            if (walls != null)
              Positioned(
                left: 0,
                right: 0,
                top: 146,
                height: 398,
                child: RawGestureDetector(
                  behavior: HitTestBehavior.translucent,
                  gestures: {
                    if (_canHold)
                      LongPressGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            LongPressGestureRecognizer
                          >(
                            () =>
                                LongPressGestureRecognizer(duration: _holdFor),
                            _listenForHold,
                          ),
                  },
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragStart: (_) => _takeOver(),
                    onHorizontalDragUpdate: (details) =>
                        _steer(details.delta.dx, _wheelSpan),
                    onHorizontalDragEnd: (details) =>
                        _letGo(details.velocity.pixelsPerSecond.dx, _wheelSpan),
                    onVerticalDragStart: (details) =>
                        _startRoll(details.localPosition.dx),
                    onVerticalDragUpdate: (details) =>
                        _rollBy(details.delta.dy),
                    onVerticalDragEnd: (details) =>
                        _endRoll(details.velocity.pixelsPerSecond.dy),
                    onTapUp: canPick
                        ? (details) =>
                              _tap(details.localPosition + const Offset(0, 146))
                        : null,
                  ),
                ),
              ),
            if (walls != null)
              Positioned(
                left: 28,
                top: 548,
                width: _Rail.width,
                height: _Rail.height,
                child: RewindLeave(
                  position: widget.position,
                  centerY: 570,
                  child: Opacity(
                    opacity: ((_ms - 700) / 400).clamp(0.0, 1.0),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onHorizontalDragStart: (_) => _takeOver(),
                      onHorizontalDragUpdate: (details) =>
                          _steer(details.delta.dx, _Rail.span),
                      onHorizontalDragEnd: (details) => _letGo(
                        details.velocity.pixelsPerSecond.dx,
                        _Rail.span,
                      ),
                      onHorizontalDragCancel: () => _letGo(0, _Rail.span),
                      onTapUp: (details) => _jump(details.localPosition.dx),
                      child: CustomPaint(
                        painter: _Rail(
                          calendar: _calendar,
                          rewound: travelled / course.length,
                          held: _dragging,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (walls != null)
              Positioned(
                left: 0,
                right: 0,
                top: 150,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: hint.shown,
                    child: Center(child: RewindHintTag(hint.text)),
                  ),
                ),
              ),
            if (landed && picked == null && !_still && !_reel)
              Positioned(
                left: 236,
                top: 500,
                child: RewindLeave(
                  position: widget.position,
                  centerY: 540,
                  child: GestureDetector(
                    onTap: _flyAgain,
                    child: Transform.scale(
                      scale: settle,
                      child: Transform.rotate(
                        angle: 0.07,
                        child: const _Again(),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  ({String text, double shown}) _hint(
    bool landed,
    double sinceLanding,
    bool canPick,
  ) {
    double window(double ms, double from, double to) =>
        ((ms - from) / 260).clamp(0.0, 1.0) * ((to - ms) / 420).clamp(0.0, 1.0);
    final texts = [
      if (!canPick) "DRAG SIDEWAYS TO FLY IT YOURSELF",
      if (canPick && !_hasPicked) "TAP A PHOTO TO PULL IT OUT",
      if (!_hasRolled) "DRAG UP OR DOWN TO SPIN IT",
      if (!canPick && !_hasHeld) "HOLD TO PAUSE",
    ];
    if (_reel || _picked != null || texts.isEmpty) return (text: "", shown: 0);
    if (!canPick) {
      final since = _guidedMs - _hintFromMs;
      final turn = (since / _hintMs).floor().clamp(0, texts.length - 1);
      return (
        text: texts[turn],
        shown: window(since, turn * _hintMs, (turn + 1) * _hintMs),
      );
    }
    final turn = (_ms / _hintMs).floor() % texts.length;
    final swapping = texts.length == 1
        ? 1.0
        : window(_ms % _hintMs, 0, _hintMs);
    return (
      text: texts[turn],
      shown: swapping * (landed ? window(sinceLanding, 900, 7000) : 1),
    );
  }

  Widget _caption(EnteFile file) {
    final day = WarpPage.taken(file);
    return _Caption(
      key: ValueKey(file),
      eyebrow:
          "A ${_weekdays[day.weekday - 1]} IN ${_monthNames[day.month - 1]}",
      title: "REMEMBER THIS?",
      body: "One moment from your year.",
      myBody: "One moment from my year.",
    );
  }

  String get _ago {
    final days = DateTime.now()
        .difference(WarpPage._instant(widget.first))
        .inDays;
    return days < 1
        ? "EARLIER TODAY"
        : "${rewindCounted(days, "DAY", "DAYS")} AGO";
  }
}

class _Caption extends StatelessWidget {
  const _Caption({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.myBody,
    super.key,
  });

  final String eyebrow;
  final String title;
  final String body;
  final String myBody;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 334,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(eyebrow, style: RewindTextStyles.display(17, height: 1.05)),
          const SizedBox(height: 10),
          RewindFitWidth(
            width: 322,
            child: RewindOutlinedText(
              title,
              style: RewindTextStyles.display(
                46,
                color: RewindColors.yellow,
                height: 0.84,
              ).copyWith(wordSpacing: 4.6),
              shadow: const Offset(1.7, 2),
            ),
          ),
          const SizedBox(height: 16),
          RewindVoice(
            you: body,
            me: myBody,
            builder: (text) => Text(text, style: RewindTextStyles.body(17)),
          ),
        ],
      ),
    );
  }
}

class _Month {
  const _Month(this.month, this.from, this.to);

  final int month;
  final double from;
  final double to;

  static List<_Month> along(_Course course, RewindAtlas? walls) {
    if (walls == null || course.rings == 0) return const [];
    double rewound(int ring) =>
        ((_Course.lead + ring * _Course.gap) / course.length).clamp(0.0, 1.0);
    final calendar = <_Month>[];
    var start = 0;
    for (var ring = 1; ring <= course.rings; ring++) {
      final month = WarpPage.taken(
        walls.files[(ring - 1) * _Course.sides],
      ).month;
      final next = ring == course.rings
          ? null
          : WarpPage.taken(walls.files[ring * _Course.sides]).month;
      if (next == month) continue;
      calendar.add(
        _Month(month, start == 0 ? 0 : rewound(start), rewound(ring)),
      );
      start = ring;
    }
    return calendar;
  }
}

class _Rail extends CustomPainter {
  _Rail({required this.calendar, required this.rewound, required this.held});

  static const width = 334.0;
  static const height = 50.0;
  static const inset = 14.0;
  static const span = width - 2 * inset;
  static const _line = 22.0;

  final List<_Month> calendar;
  final double rewound;
  final bool held;

  static double _x(double rewound) => inset + span * (1 - rewound);

  @override
  void paint(Canvas canvas, Size size) {
    Paint stroke(Color color, double width) => Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    final thumb = Offset(_x(rewound), _line);
    canvas.drawLine(
      const Offset(inset, _line),
      const Offset(inset + span, _line),
      stroke(RewindColors.ink, 9),
    );
    canvas.drawLine(
      const Offset(inset, _line),
      const Offset(inset + span, _line),
      stroke(const Color(0xFF4B4478), 5),
    );
    canvas.drawLine(
      thumb,
      const Offset(inset + span, _line),
      stroke(RewindColors.hotPink, 5),
    );
    for (final month in calendar) {
      final from = _x(month.from);
      final to = _x(month.to);
      if (month.to < 1) {
        canvas.drawLine(
          Offset(to, _line - 6),
          Offset(to, _line + 6),
          stroke(RewindColors.cream.withValues(alpha: 0.7), 1.6),
        );
      }
      if (from - to < 20) continue;
      final here = rewound >= month.from && rewound <= month.to;
      final label = TextPainter(
        text: TextSpan(
          text: _months[month.month - 1],
          style: RewindTextStyles.numeral(
            9,
            color: here
                ? RewindColors.yellow
                : RewindColors.cream.withValues(alpha: 0.72),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset((from + to - label.width) / 2, _line + 11));
      label.dispose();
    }
    canvas.drawCircle(thumb, held ? 13 : 11, Paint()..color = RewindColors.ink);
    canvas.drawCircle(
      thumb,
      held ? 10 : 8,
      Paint()..color = RewindColors.yellow,
    );
  }

  @override
  bool shouldRepaint(_Rail oldDelegate) =>
      oldDelegate.rewound != rewound ||
      oldDelegate.held != held ||
      oldDelegate.calendar != calendar;
}

class _Counter extends StatelessWidget {
  const _Counter(this.label, this.date, {required this.paused});

  final String label;
  final String? date;
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final date = this.date;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 9, 16, 8),
      decoration: BoxDecoration(
        color: RewindColors.ink,
        border: Border.all(color: RewindColors.cream, width: 3),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Color(0xFF000000), offset: Offset(4, 5)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (date != null) ...[
            Icon(
              paused ? Icons.pause_rounded : Icons.fast_rewind_rounded,
              color: RewindColors.cream,
              size: 22,
            ),
            const SizedBox(width: 6),
          ],
          Text(label, style: RewindTextStyles.display(15, height: 1.1)),
          if (date != null) ...[
            const SizedBox(width: 12),
            SizedBox(
              width: 86,
              child: Text(
                date,
                textAlign: TextAlign.right,
                style: RewindTextStyles.display(
                  24,
                  color: RewindColors.yellow,
                  height: 1.05,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Again extends StatelessWidget {
  const _Again();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 12, 5),
      decoration: BoxDecoration(
        color: RewindColors.hotPink,
        border: Border.all(color: RewindColors.ink, width: 3),
        borderRadius: BorderRadius.circular(7),
        boxShadow: const [
          BoxShadow(color: RewindColors.ink, offset: Offset(3, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.fast_rewind_rounded,
            color: RewindColors.cream,
            size: 20,
          ),
          const SizedBox(width: 4),
          Text("FLY AGAIN", style: RewindTextStyles.display(15, height: 1.1)),
        ],
      ),
    );
  }
}

class _Print extends StatelessWidget {
  const _Print({
    required this.width,
    required this.photo,
    required this.caption,
  });

  final double width;
  final Widget photo;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        RewindPolaroid(photo: photo, width: width),
        Padding(
          padding: EdgeInsets.only(bottom: width * 0.096),
          child: Text(
            caption,
            style: RewindTextStyles.film(15, color: RewindColors.ink),
          ),
        ),
      ],
    );
  }
}

class _Course {
  const _Course(this.rings);

  static const sides = 6;
  static const gap = 1.06;
  static const lead = 0.5;
  static const landing = 2.9;
  static const sighted = 10.0;
  static const focal = 250.0;
  static const vanish = Offset(195, 390);
  static const nearest = 0.14;
  static const farthest = 15.0;
  static const _straight = 9.0;

  final int rings;

  double get end => lead + rings * gap;

  double get length => max(1.0, end - landing);

  Offset bend(double along) =>
      Offset(1.5 * sin(0.17 * along), 1.05 * sin(0.12 * along + 1.1)) *
      ((length - along) / _straight).clamp(0.0, 1.0);

  Offset project(double along, double travelled, double turn, double reach) {
    final lateral =
        bend(along) - bend(travelled) + Offset.fromDirection(turn, reach);
    return vanish + lateral * (focal / (along - travelled));
  }

  double twist(int ring, double travelled, double roll) =>
      0.05 * travelled + ring * 0.21 + roll;

  ({double near, double far})? stretch(int ring, double travelled) {
    final along = lead + ring * gap;
    final far = along + gap * 0.93;
    final near = max(along, travelled + nearest);
    return far - near < 0.02 || along - travelled > farthest
        ? null
        : (near: near, far: far);
  }

  List<Offset> panel(
    int ring,
    int side,
    double travelled,
    double roll,
    double near,
    double far,
  ) {
    final turn = twist(ring, travelled, roll);
    final from = turn + (side + 0.035) * 2 * pi / sides;
    final to = turn + (side + 0.965) * 2 * pi / sides;
    return [
      project(far, travelled, to, 1),
      project(far, travelled, from, 1),
      project(near, travelled, from, 1),
      project(near, travelled, to, 1),
    ];
  }

  int? panelAt(Offset point, double travelled, double roll) {
    for (var ring = 0; ring < rings; ring++) {
      final stretch = this.stretch(ring, travelled);
      if (stretch == null) continue;
      for (var side = 0; side < sides; side++) {
        final corners = panel(
          ring,
          side,
          travelled,
          roll,
          stretch.near,
          stretch.far,
        );
        var turns = 0;
        for (var corner = 0; corner < 4; corner++) {
          final edge = corners[(corner + 1) % 4] - corners[corner];
          final reach = point - corners[corner];
          turns += (edge.dx * reach.dy - edge.dy * reach.dx) > 0 ? 1 : -1;
        }
        if (turns.abs() == 4) return ring * sides + side;
      }
    }
    return null;
  }
}

class _Tube extends CustomPainter {
  _Tube({
    required this.walls,
    required this.course,
    required this.travelled,
    required this.roll,
    required this.speed,
    required this.arrival,
    required this.sinceLanding,
    required this.dim,
    required this.ms,
  });

  static const _night = Color(0xFF120E2E);

  final RewindAtlas? walls;
  final _Course course;
  final double travelled;
  final double roll;
  final double speed;
  final double arrival;
  final double sinceLanding;
  final double dim;
  final double ms;

  Offset _project(double along, double turn, [double reach = 1]) =>
      course.project(along, travelled, turn, reach);

  Color _shade(double depth) {
    final light =
        ((1.2 - depth / 10).clamp(0.1, 1.0) *
                (1 - 0.42 * arrival) *
                (1 - 0.55 * dim) *
                255)
            .round();
    return Color.fromARGB(255, light, light, light);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final walls = this.walls;
    if (walls == null) {
      _static(canvas);
      return;
    }
    const sides = _Course.sides;
    final gates = <(int, double, double)>[];
    final wall = Paint()..filterQuality = FilterQuality.medium;
    for (var ring = course.rings - 1; ring >= 0; ring--) {
      final stretch = course.stretch(ring, travelled);
      if (stretch == null) continue;
      final along = _Course.lead + ring * _Course.gap;
      final (:near, :far) = stretch;
      wall.colorFilter = ColorFilter.mode(
        _shade((near + far) / 2 - travelled),
        BlendMode.modulate,
      );
      for (var side = 0; side < sides; side++) {
        final source = walls.source(ring * sides + side);
        final corners = course.panel(ring, side, travelled, roll, near, far);
        _panel(
          canvas,
          walls.image,
          Rect.fromLTRB(
            source.left,
            source.top,
            source.right,
            source.bottom - source.height * (near - along) / (far - along),
          ),
          corners[0],
          corners[1],
          corners[2],
          corners[3],
          wall,
        );
      }
      final month = WarpPage.taken(walls.files[ring * sides]).month;
      final earlier = ring + 1 < course.rings
          ? WarpPage.taken(walls.files[(ring + 1) * sides]).month
          : month;
      if (earlier != month && far < course.length - 3) {
        gates.add((
          earlier,
          far + _Course.gap * 0.035,
          course.twist(ring, travelled, roll),
        ));
      }
    }
    for (final (month, along, twist) in gates) {
      _gate(canvas, month, along, twist);
    }
    _streaks(canvas);
    _touchdown(canvas);
  }

  static void _panel(
    Canvas canvas,
    ui.Image image,
    Rect source,
    Offset topLeft,
    Offset topRight,
    Offset bottomRight,
    Offset bottomLeft,
    Paint paint,
  ) {
    final acrossX = topRight.dx - bottomRight.dx;
    final acrossY = topRight.dy - bottomRight.dy;
    final downX = bottomLeft.dx - bottomRight.dx;
    final downY = bottomLeft.dy - bottomRight.dy;
    final skewX = topLeft.dx - topRight.dx + bottomRight.dx - bottomLeft.dx;
    final skewY = topLeft.dy - topRight.dy + bottomRight.dy - bottomLeft.dy;
    final spread = acrossX * downY - downX * acrossY;
    if (spread.abs() < 1e-6) return;
    final g = (skewX * downY - downX * skewY) / spread;
    final h = (acrossX * skewY - skewX * acrossY) / spread;
    canvas.save();
    canvas.transform(
      Float64List.fromList([
        topRight.dx - topLeft.dx + g * topRight.dx,
        topRight.dy - topLeft.dy + g * topRight.dy,
        0,
        g,
        bottomLeft.dx - topLeft.dx + h * bottomLeft.dx,
        bottomLeft.dy - topLeft.dy + h * bottomLeft.dy,
        0,
        h,
        0,
        0,
        1,
        0,
        topLeft.dx,
        topLeft.dy,
        0,
        1,
      ]),
    );
    canvas.drawImageRect(image, source, const Rect.fromLTWH(0, 0, 1, 1), paint);
    canvas.restore();
  }

  void _gate(Canvas canvas, int month, double along, double twist) {
    final depth = along - travelled;
    if (depth < 0.5) return;
    const sides = _Course.sides;
    final near = ((depth - 0.5) / 1.6).clamp(0.0, 1.0);
    final hoop = Path();
    for (var side = 0; side <= sides; side++) {
      final corner = _project(along, twist + side * 2 * pi / sides);
      side == 0
          ? hoop.moveTo(corner.dx, corner.dy)
          : hoop.lineTo(corner.dx, corner.dy);
    }
    final width = (14 / depth).clamp(1.2, 16.0);
    canvas.drawPath(
      hoop,
      Paint()
        ..color = RewindColors.ink.withValues(alpha: near)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width * 1.7
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(
      hoop,
      Paint()
        ..color = (month.isEven ? RewindColors.hotPink : RewindColors.yellow)
            .withValues(alpha: near)
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeJoin = StrokeJoin.round,
    );
    final legible = near * (1 - arrival * 4).clamp(0.0, 1.0);
    if (depth > 9 || legible <= 0) return;
    final label = TextPainter(
      text: TextSpan(
        text: _months[month - 1],
        style: RewindTextStyles.display(
          64,
          color: RewindColors.cream.withValues(alpha: legible),
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final center = _project(along, 0, 0);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(min(4.5, 1.9 / depth));
    label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
    canvas.restore();
    label.dispose();
  }

  void _streaks(Canvas canvas) {
    if (speed < 0.05) return;
    final random = Random(3);
    for (var i = 0; i < 44; i++) {
      final direction = Offset.fromDirection(random.nextDouble() * 2 * pi);
      final phase =
          (random.nextDouble() + ms / (520 + 300 * random.nextDouble())) % 1;
      final from = 40 + 520 * phase * phase;
      canvas.drawLine(
        _Course.vanish + direction * from,
        _Course.vanish + direction * (from + (26 + 150 * phase) * speed),
        Paint()
          ..color = RewindColors.cream.withValues(alpha: 0.5 * speed * phase)
          ..strokeWidth = 1 + 2.4 * phase
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _touchdown(Canvas canvas) {
    final dusk = max(arrival * arrival, dim);
    if (dusk <= 0) return;
    canvas.drawRect(
      const Rect.fromLTRB(-600, 430, 990, 1500),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 430),
          const Offset(0, 640),
          [_night.withValues(alpha: 0), _night.withValues(alpha: 0.94 * dusk)],
        ),
    );
    final ripple = sinceLanding / 620;
    if (ripple <= 0 || ripple >= 1) return;
    for (final (delay, colour) in [
      (0.0, RewindColors.yellow),
      (0.22, RewindColors.hotPink),
    ]) {
      final spread = Curves.easeOutCubic.transform(
        ((ripple - delay) / (1 - delay)).clamp(0.0, 1.0),
      );
      if (spread <= 0) continue;
      final hoop = Path();
      for (var side = 0; side <= _Course.sides; side++) {
        final corner =
            _Course.vanish +
            Offset.fromDirection(
              side * 2 * pi / _Course.sides + pi / 6,
              120 + 420 * spread,
            );
        side == 0
            ? hoop.moveTo(corner.dx, corner.dy)
            : hoop.lineTo(corner.dx, corner.dy);
      }
      canvas.drawPath(
        hoop,
        Paint()
          ..color = colour.withValues(alpha: 0.85 * (1 - spread))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 + 16 * (1 - spread)
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  void _static(Canvas canvas) {
    for (var hoop = 1; hoop <= 7; hoop++) {
      final beat = (hoop + ms / 420) % 7;
      canvas.drawCircle(
        _Course.vanish,
        18 + beat * beat * 9,
        Paint()
          ..color = RewindColors.cream.withValues(alpha: 0.05 + 0.04 * beat)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 + beat,
      );
    }
  }

  @override
  bool shouldRepaint(_Tube oldDelegate) =>
      oldDelegate.walls != walls ||
      oldDelegate.travelled != travelled ||
      oldDelegate.roll != roll ||
      oldDelegate.dim != dim ||
      oldDelegate.ms != ms;
}
