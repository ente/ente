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
import "package:photos/ui/rewind/theme/rewind_motion.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_hint.dart";
import "package:photos/ui/rewind/widgets/rewind_numbers.dart";
import "package:photos/ui/rewind/widgets/rewind_photo.dart";
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
      tile: 192,
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
  Duration? get reelHold => _flightThen(RewindMotion.reelReadingMs);

  @override
  Duration? get clipHold => _flightThen(_clipLandedMs);

  static const _clipLandedMs = 2500;

  static Duration _flightThen(int landedMs) => Duration(
    milliseconds:
        (_FlightState._countdownMs + _FlightState._flightMs).round() + landedMs,
  );

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
          active: isActive && !RewindPageScope.coveredOf(context),
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
  static const _coastMs = 450.0;
  static const _pixelsPerUnit = 68.0;
  static const _touchTop = 70.0;
  static const _touchBottom = 770.0;
  static const _flyAbove = 700.0;
  static const _rollSpan = 140.0;
  static const _rollCoastMs = 520.0;
  static const _detent = pi / 3;
  static const _holdFor = Duration(milliseconds: 250);
  static const _holdSlop = 12.0;
  static const _brakeMs = 90.0;
  static const _hintFromMs = 1500.0;
  static const _hintMs = 2200.0;
  static const _restMs = 500.0;
  static const _pickedAt = Offset(195, 356);

  static const _flightMs = 9500.0;
  static const _countdownMs = 900.0;

  late final _reel = RewindPageScope.reelOf(context);
  late final Ticker _ticker = createTicker(_onTick);
  late final AnimationController _pull = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    reverseDuration: const Duration(milliseconds: 220),
  )..addStatusListener(_onPull);
  late final _Course _course = _Course(
    (widget.walls?.length ?? 0) ~/ _Course.sides,
  );
  late final ImageShader? _shader = switch (widget.walls) {
    final walls? => ImageShader(
      walls.image,
      TileMode.clamp,
      TileMode.clamp,
      Matrix4.identity().storage,
      filterQuality: FilterQuality.medium,
    ),
    null => null,
  };
  final _landingPhoto = GlobalKey<RewindPhotoState>();
  final _pickedPhoto = GlobalKey<RewindPhotoState>();

  var _last = Duration.zero;
  var _ms = 0.0;
  var _flownMs = 0.0;
  var _guidedMs = 0.0;
  var _travelled = 0.0;
  var _previous = 0.0;
  var _velocity = 0.0;
  var _pace = 0.0;
  var _heading = 1.0;
  var _flewMs = double.negativeInfinity;
  var _piloted = false;
  var _still = false;
  var _dragging = false;
  var _roll = 0.0;
  var _rollRate = 0.0;
  var _rollSide = 1.0;
  var _rolling = false;
  var _hasFlown = false;
  var _hasRolled = false;
  var _detents = 0;
  var _held = false;
  var _hasHeld = false;
  var _heldBy = Offset.zero;
  Axis? _heldAxis;
  var _brake = 0.0;
  double? _landedMs;
  var _gate = -1;
  int? _picked;
  var _pickedFrom = _Course.vanish;
  var _hasPicked = false;

  bool get _landed =>
      widget.walls != null && _travelled >= _course.length - 0.01;

  bool get _canHold =>
      _held || (!_piloted && !_landed) || _velocity != 0 || _rollRate != 0;

  bool get _idle => _piloted && !_held && _pace < 0.04;

  bool get _canPick => widget.walls != null && _piloted && !_landed;

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
    _shader?.dispose();
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
    final moved = _travelled - _previous;
    final rate = moved.abs() / dt;
    if (rate > 0.0004) _heading = moved.sign;
    if (moved != 0) _flewMs = _ms;
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
    if (_dragging || _velocity == 0) return;
    final step = min(dt, 50.0);
    _travelled = (_travelled + _velocity * step).clamp(0.0, length);
    _velocity *= exp(-step / _coastMs);
    if (_velocity.abs() < 0.0003 || _travelled <= 0 || _travelled >= length) {
      _velocity = 0;
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
      max(0, ((_travelled - _Course.lead) / _Course.depth).floor()),
    );
    return WarpPage.taken(walls.files[ring * _Course.sides]);
  }

  void _takeOver() {
    _release();
    _piloted = true;
    _hasFlown = true;
    _dragging = true;
    _velocity = 0;
  }

  void _flyBy(double dy) {
    _flewMs = _ms;
    _travelled = (_travelled - dy / _pixelsPerUnit).clamp(0.0, _course.length);
  }

  void _letGo(double pixelsPerSecond) {
    _flewMs = _ms;
    _dragging = false;
    _velocity = -pixelsPerSecond / _pixelsPerUnit / 1000;
  }

  bool _yields(bool deeper) =>
      _picked == null &&
      _ms - _flewMs >= _restMs &&
      (deeper ? _landed : _travelled <= 0.002);

  void _listenForFlight(_FlightRecognizer recognizer) {
    recognizer.onStart = (_) => _takeOver();
    recognizer.onUpdate = (details) => _flyBy(details.delta.dy);
    recognizer.onEnd = (details) => _letGo(details.primaryVelocity ?? 0);
    recognizer.onCancel = () => _letGo(0);
  }

  double _sideOf(Offset at) => at.dy < _Course.vanish.dy ? 1 : -1;

  void _startRoll(Offset at) {
    _release();
    _rolling = true;
    _rollRate = 0;
    _rollSide = _sideOf(at);
  }

  void _rollBy(double dx) {
    _roll += _rollSide * dx / _rollSpan;
    _hasRolled = true;
  }

  void _endRoll(double pixelsPerSecond) {
    _rolling = false;
    _rollRate = _still ? 0 : _rollSide * pixelsPerSecond / _rollSpan / 1000;
  }

  void _listenForSpin(HorizontalDragGestureRecognizer recognizer) {
    recognizer.onStart = (details) =>
        _startRoll(details.localPosition + const Offset(0, _touchTop));
    recognizer.onUpdate = (details) => _rollBy(details.delta.dx);
    recognizer.onEnd = (details) => _endRoll(details.primaryVelocity ?? 0);
    recognizer.onCancel = () => _endRoll(0);
  }

  void _listenForHold(LongPressGestureRecognizer recognizer) {
    recognizer.onLongPressStart = (details) =>
        _hold(details.localPosition + const Offset(0, _touchTop));
    recognizer.onLongPressMoveUpdate = (details) =>
        _holdMove(details.localOffsetFromOrigin);
    recognizer.onLongPressEnd = (details) =>
        _letHoldGo(details.velocity.pixelsPerSecond);
    recognizer.onLongPressCancel = () => _letHoldGo(Offset.zero);
  }

  void _hold(Offset at) {
    _release();
    _held = true;
    _hasHeld = true;
    _heldBy = Offset.zero;
    _heldAxis = null;
    _velocity = 0;
    _rollRate = 0;
    _rollSide = _sideOf(at);
    HapticFeedback.selectionClick();
  }

  void _holdMove(Offset moved) {
    final delta = moved - _heldBy;
    _heldBy = moved;
    switch (_heldAxis) {
      case Axis.vertical:
        _flyBy(delta.dy);
      case Axis.horizontal:
        _rollBy(delta.dx);
      case null:
        if (moved.distance < _holdSlop) return;
        if (moved.dy.abs() > moved.dx.abs()) {
          _heldAxis = Axis.vertical;
          _takeOver();
        } else {
          _heldAxis = Axis.horizontal;
          _rolling = true;
        }
    }
  }

  void _letHoldGo(Offset pixelsPerSecond) {
    if (!_held) return;
    _held = false;
    switch (_heldAxis) {
      case Axis.vertical:
        _letGo(pixelsPerSecond.dy);
      case Axis.horizontal:
        _endRoll(pixelsPerSecond.dx);
      case null:
    }
  }

  void _listenForTap(TapGestureRecognizer recognizer) {
    recognizer.onTapUp = (details) =>
        _tap(details.localPosition + const Offset(0, _touchTop));
  }

  void _flyAgain() {
    _release();
    _piloted = false;
    _flownMs = 0;
    _guidedMs = 0;
    _velocity = 0;
    _gate = -1;
  }

  void _release() {
    if (_picked != null) _pull.reverse();
  }

  void _onPull(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) setState(() => _picked = null);
  }

  Rect _printAt(Offset center) => Rect.fromCenter(
    center: center,
    width: _printWidth,
    height: _printWidth * 1.22,
  );

  void _tap(Offset at) {
    if (_picked != null) {
      if (_pull.status.isForwardOrCompleted &&
          _printAt(_pickedAt).contains(at)) {
        _pickedPhoto.currentState?.zoom();
      } else {
        _release();
      }
      return;
    }
    if (_landed && _printAt(_Course.vanish).contains(at)) {
      _landingPhoto.currentState?.zoom();
      return;
    }
    final panel = _canPick ? _course.panelAt(at, _travelled, _roll) : null;
    if (panel == null) {
      if (!_landed) return;
      final navigator = RewindPageScope.navigatorOf(context);
      at.dx < RewindStage.size.width / 3
          ? navigator?.previous()
          : navigator?.next();
      return;
    }
    HapticFeedback.lightImpact();
    _velocity = 0;
    _rollRate = 0;
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
    const door = _Course.vanish;
    final settle = Curves.easeOutBack.transform(
      (sinceLanding / 420).clamp(0.0, 1.0),
    );
    final picked = _picked;
    final pulled = Curves.easeOutCubic.transform(_pull.value);
    final canPick = _canPick;
    final forward = _piloted && _heading < 0;
    final hint = _hint(landed, sinceLanding, canPick);
    return Stack(
      fit: StackFit.expand,
      children: [
        RewindShareable(
          enabled: walls != null && widget.landing != null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: RewindColors.outline),
              RewindStage(
                children: [
                  Positioned.fill(
                    child: RewindLeave(
                      position: widget.position,
                      centerY: 400,
                      child: CustomPaint(
                        painter: _Tube(
                          walls: walls,
                          shader: _shader,
                          course: course,
                          travelled: travelled,
                          roll: _roll,
                          arrival: arrival,
                          dim: pulled,
                          ms: _ms,
                        ),
                      ),
                    ),
                  ),
                  if (walls != null && passing != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: _Course.vanish.dy - 40,
                      height: 80,
                      child: RewindLeave(
                        position: widget.position,
                        centerY: _Course.vanish.dy,
                        child: IgnorePointer(
                          child: Opacity(
                            opacity:
                                (1.6 - arrival * 2).clamp(0.0, 1.0) *
                                (1 - pulled),
                            child: Center(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 240),
                                reverseDuration: Duration.zero,
                                switchInCurve: Curves.easeOut,
                                transitionBuilder: (child, animation) =>
                                    FadeTransition(
                                      opacity: animation,
                                      child: SlideTransition(
                                        position: Tween(
                                          begin: const Offset(0, 0.14),
                                          end: Offset.zero,
                                        ).animate(animation),
                                        child: ScaleTransition(
                                          scale: Tween(
                                            begin: 0.96,
                                            end: 1.0,
                                          ).animate(animation),
                                          child: child,
                                        ),
                                      ),
                                    ),
                                child: _Month(
                                  _monthNames[passing.month - 1],
                                  key: ValueKey(passing.month),
                                ),
                              ),
                            ),
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
                                      key: _landingPhoto,
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
                                      photo: widget.photo(
                                        walls.files[picked],
                                        key: _pickedPhoto,
                                      ),
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
                                  : _held
                                  ? "PAUSED"
                                  : _idle
                                  ? "TIME TRAVEL"
                                  : forward
                                  ? "FAST FORWARD"
                                  : "REWINDING",
                              passing == null || landed
                                  ? null
                                  : "${passing.day} ${_months[passing.month - 1]}",
                              icon: _held
                                  ? Icons.pause_rounded
                                  : _idle
                                  ? Icons.swap_vert_rounded
                                  : forward
                                  ? Icons.fast_forward_rounded
                                  : Icons.fast_rewind_rounded,
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
                                body: "Your first photo of the year.",
                                myBody: "My first photo of the year.",
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
                top: _touchTop,
                height: _touchBottom - _touchTop,
                child: RawGestureDetector(
                  behavior: HitTestBehavior.translucent,
                  gestures: {
                    _FlightRecognizer:
                        GestureRecognizerFactoryWithHandlers<_FlightRecognizer>(
                          () => _FlightRecognizer(
                            above: _flyAbove - _touchTop,
                            yields: _yields,
                          ),
                          _listenForFlight,
                        ),
                    HorizontalDragGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          HorizontalDragGestureRecognizer
                        >(HorizontalDragGestureRecognizer.new, _listenForSpin),
                    if (_canHold)
                      LongPressGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            LongPressGestureRecognizer
                          >(
                            () =>
                                LongPressGestureRecognizer(duration: _holdFor),
                            _listenForHold,
                          ),
                    TapGestureRecognizer:
                        GestureRecognizerFactoryWithHandlers<
                          TapGestureRecognizer
                        >(TapGestureRecognizer.new, _listenForTap),
                  },
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
    final texts = landed
        ? ["TAP OR SWIPE UP TO GO ON", if (!_hasFlown) "SWIPE DOWN TO FLY BACK"]
        : [
            if (!_hasFlown) "SWIPE UP OR DOWN TO FLY",
            if (canPick && !_hasPicked) "TAP A PHOTO TO PULL IT OUT",
            if (!_hasRolled) "SWIPE SIDEWAYS TO SPIN IT",
            if (!canPick && !_hasHeld) "HOLD TO PAUSE",
          ];
    if (_reel || _picked != null || texts.isEmpty) return (text: "", shown: 0);
    if (!canPick && !landed) {
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
      shown:
          swapping * (landed ? window(sinceLanding, 900, double.infinity) : 1),
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

class _Counter extends StatelessWidget {
  const _Counter(this.label, this.date, {required this.icon});

  final String label;
  final String? date;
  final IconData icon;

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
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (date != null) ...[
              Icon(icon, color: RewindColors.cream, size: 22),
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
      ),
    );
  }
}

class _Month extends StatelessWidget {
  const _Month(this.name, {super.key});

  final String name;

  @override
  Widget build(BuildContext context) {
    return RewindOutlinedText(
      name,
      style: RewindTextStyles.display(30, height: 1.1, letterSpacing: 0.2),
      outline: 2.5,
      shadow: const Offset(0, 4),
      ink: RewindColors.outline,
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
  _Course(this.rings) : _boxes = List.filled(rings * sides, null);

  static const sides = 6;
  static const depth = 1.4;
  static const lead = 0.5;
  static const landing = 2.9;
  static const sighted = 10.0;
  static const focal = 560.0;
  static const vanish = Offset(195, 390);
  static const nearest = 0.14;
  static const fogFrom = 12.7;
  static const fogTo = 23.3;
  static const _twist = 0.0786;
  static const _drift = 0.018;
  static const _rounding = 0.22;
  static const _across = 8;
  static const _deep = 4;

  final int rings;
  final List<Rect?> _boxes;

  double get end => lead + rings * depth;

  double get length => max(1.0, end - landing);

  double start(int ring) => lead + ring * depth;

  ({double from, double to}) _along(int ring, int side) {
    final from = start(ring) - (side.isOdd ? depth / 2 : 0.0);
    return (from: from, to: ring == rings - 1 ? end : from + depth);
  }

  static Offset _corner(int index) =>
      Offset.fromDirection(index * pi / 3 + pi / 6);

  static Offset _rounded(int corner, double t) {
    final tip = _corner(corner);
    final from = Offset.lerp(tip, _corner(corner - 1), _rounding)!;
    final to = Offset.lerp(tip, _corner(corner + 1), _rounding)!;
    return from * ((1 - t) * (1 - t)) + tip * (2 * (1 - t) * t) + to * (t * t);
  }

  static Offset _rim(double around) {
    final corner = around.floor();
    final t = around - corner;
    if (t < _rounding) return _rounded(corner, 0.5 + t / (2 * _rounding));
    if (t > 1 - _rounding) {
      return _rounded(corner + 1, (t - 1 + _rounding) / (2 * _rounding));
    }
    return Offset.lerp(_corner(corner), _corner(corner + 1), t)!;
  }

  static Offset _turn(Offset point, double angle) {
    final c = cos(angle);
    final s = sin(angle);
    return Offset(point.dx * c - point.dy * s, point.dx * s + point.dy * c);
  }

  Offset point(double around, double along, double travelled, double roll) =>
      vanish +
      _turn(_rim(around), _twist * along + _drift * travelled + roll) *
          (focal / (along - travelled));

  static Offset _decal(double from, double around, double along) =>
      _turn(_rim(around), _twist * along + _drift * (from - depth)) /
      (along - from + depth);

  Rect _box(int ring, int side) =>
      _boxes[ring * sides + side] ??= _measure(ring, side);

  Rect _measure(int ring, int side) {
    final along = _along(ring, side);
    var box = Rect.fromCenter(
      center: _decal(along.from, side.toDouble(), along.from),
      width: 0,
      height: 0,
    );
    for (var row = 0; row <= _deep; row++) {
      for (var step = 0; step <= _across; step++) {
        final decal = _decal(
          along.from,
          side + step / _across,
          along.from + (along.to - along.from) * row / _deep,
        );
        box = box.expandToInclude(
          Rect.fromCenter(center: decal, width: 0, height: 0),
        );
      }
    }
    return box;
  }

  ({double near, double far})? reach(int ring, int side, double travelled) {
    final along = _along(ring, side);
    final near = max(along.from, travelled + nearest);
    final far = along.to;
    return far - near < 0.01 || near - travelled > fogTo
        ? null
        : (near: near, far: far);
  }

  static double _row(({double near, double far}) reach, int row) =>
      reach.near + (reach.far - reach.near) * row / _deep;

  void mesh(
    int ring,
    int side,
    double travelled,
    double roll,
    Rect tile,
    List<double> positions,
    List<double> pixels,
    List<int> indices,
  ) {
    final reach = this.reach(ring, side, travelled);
    if (reach == null) return;
    final from = _along(ring, side).from;
    final box = _box(ring, side);
    final wide = min(1.0, box.width / box.height);
    final tall = min(1.0, box.height / box.width);
    final first = positions.length ~/ 2;
    for (var row = 0; row <= _deep; row++) {
      final along = _row(reach, row);
      for (var step = 0; step <= _across; step++) {
        final around = side + step / _across;
        final seen = point(around, along, travelled, roll);
        final decal = _decal(from, around, along);
        final u = ((decal.dx - box.left) / box.width - 0.5) * wide + 0.5;
        final v = ((decal.dy - box.top) / box.height - 0.5) * tall + 0.5;
        positions
          ..add(seen.dx)
          ..add(seen.dy);
        pixels
          ..add(tile.left + 1 + u * (tile.width - 2))
          ..add(tile.top + 1 + v * (tile.height - 2));
        if (row == _deep || step == _across) continue;
        final corner = first + row * (_across + 1) + step;
        final below = corner + _across + 1;
        indices.addAll([
          corner,
          corner + 1,
          below + 1,
          corner,
          below + 1,
          below,
        ]);
      }
    }
  }

  int? panelAt(Offset at, double travelled, double roll) {
    for (var ring = 0; ring < rings; ring++) {
      for (var side = 0; side < sides; side++) {
        final reach = this.reach(ring, side, travelled);
        if (reach == null) continue;
        Offset seen(double around, int row) =>
            point(around, _row(reach, row), travelled, roll);
        final outline = [
          for (var step = 0; step <= _across; step++)
            seen(side + step / _across, 0),
          for (var row = 1; row < _deep; row++) seen(side + 1.0, row),
          for (var step = _across; step >= 0; step--)
            seen(side + step / _across, _deep),
          for (var row = _deep - 1; row > 0; row--) seen(side.toDouble(), row),
        ];
        if (_encloses(outline, at)) return ring * sides + side;
      }
    }
    return null;
  }

  static bool _encloses(List<Offset> outline, Offset at) {
    var inside = false;
    for (var i = 0, j = outline.length - 1; i < outline.length; j = i++) {
      final a = outline[i];
      final b = outline[j];
      if ((a.dy > at.dy) != (b.dy > at.dy) &&
          at.dx < (b.dx - a.dx) * (at.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        inside = !inside;
      }
    }
    return inside;
  }
}

class _Tube extends CustomPainter {
  _Tube({
    required this.walls,
    required this.shader,
    required this.course,
    required this.travelled,
    required this.roll,
    required this.arrival,
    required this.dim,
    required this.ms,
  });

  static const _fogSteps = 8;

  final RewindAtlas? walls;
  final ImageShader? shader;
  final _Course course;
  final double travelled;
  final double roll;
  final double arrival;
  final double dim;
  final double ms;

  @override
  void paint(Canvas canvas, Size size) {
    final walls = this.walls;
    final shader = this.shader;
    if (walls == null || shader == null) {
      _static(canvas);
      return;
    }
    final positions = <double>[];
    final pixels = <double>[];
    final indices = <int>[];
    for (var ring = course.rings - 1; ring >= 0; ring--) {
      for (var side = 0; side < _Course.sides; side++) {
        course.mesh(
          ring,
          side,
          travelled,
          roll,
          walls.source(ring * _Course.sides + side),
          positions,
          pixels,
          indices,
        );
      }
    }
    if (indices.isNotEmpty) {
      final tube = ui.Vertices.raw(
        ui.VertexMode.triangles,
        Float32List.fromList(positions),
        textureCoordinates: Float32List.fromList(pixels),
        indices: Uint16List.fromList(indices),
      );
      canvas.drawVertices(
        tube,
        BlendMode.srcOver,
        Paint()
          ..shader = shader
          ..colorFilter = _fade((1 - 0.42 * arrival) * (1 - 0.55 * dim)),
      );
      tube.dispose();
    }
    _fog(canvas);
    _dusk(canvas);
  }

  static ColorFilter? _fade(double light) {
    if (light >= 1) return null;
    final lift = (1 - light) * RewindColors.outline.r * 255;
    return ColorFilter.matrix([
      light,
      0,
      0,
      0,
      lift,
      0,
      light,
      0,
      0,
      lift,
      0,
      0,
      light,
      0,
      lift,
      0,
      0,
      0,
      1,
      0,
    ]);
  }

  void _fog(Canvas canvas) {
    const edge = _Course.focal * 0.9 / _Course.fogFrom;
    final colors = <Color>[];
    final stops = <double>[];
    for (var step = 0; step <= _fogSteps; step++) {
      final along = step == 0
          ? double.infinity
          : _Course.focal * 0.9 / (edge * step / _fogSteps);
      final thick =
          ((along - _Course.fogFrom) / (_Course.fogTo - _Course.fogFrom)).clamp(
            0.0,
            1.0,
          );
      colors.add(RewindColors.outline.withValues(alpha: thick));
      stops.add(step / _fogSteps);
    }
    canvas.drawCircle(
      _Course.vanish,
      edge,
      Paint()..shader = ui.Gradient.radial(_Course.vanish, edge, colors, stops),
    );
  }

  void _dusk(Canvas canvas) {
    final dusk = max(arrival * arrival, dim);
    if (dusk <= 0) return;
    canvas.drawRect(
      const Rect.fromLTRB(-600, 430, 990, 1500),
      Paint()
        ..shader =
            ui.Gradient.linear(const Offset(0, 430), const Offset(0, 640), [
              RewindColors.outline.withValues(alpha: 0),
              RewindColors.outline.withValues(alpha: 0.94 * dusk),
            ]),
    );
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
      oldDelegate.arrival != arrival ||
      oldDelegate.dim != dim ||
      oldDelegate.ms != ms;
}

class _FlightRecognizer extends VerticalDragGestureRecognizer {
  _FlightRecognizer({required this.above, required this.yields});

  static const _decideAfter = 3.0;

  final double above;
  final bool Function(bool deeper) yields;
  var _moved = 0.0;
  var _decided = false;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      event.localPosition.dy < above && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _moved = 0;
    _decided = false;
    super.addAllowedPointer(event);
  }

  @override
  void acceptGesture(int pointer) {
    _decided = true;
    super.acceptGesture(pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (!_decided && event is PointerMoveEvent) {
      _moved += event.delta.dy;
      if (_moved.abs() > _decideAfter && yields(_moved < 0)) {
        _decided = true;
        resolve(GestureDisposition.rejected);
        stopTrackingPointer(event.pointer);
        return;
      }
    }
    super.handleEvent(event);
  }
}
