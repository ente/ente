import "dart:async";
import "dart:math";

import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:photos/models/file/file.dart";
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/story/rewind_face.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_keyframes.dart";
import "package:photos/ui/rewind/widgets/rewind_layer.dart";
import "package:photos/ui/rewind/widgets/rewind_numbers.dart";
import "package:photos/ui/rewind/widgets/rewind_photo.dart";
import "package:photos/ui/rewind/widgets/rewind_photo_frames.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

class PhotoBoothPage extends RewindPage {
  const PhotoBoothPage({
    required this.person,
    required this.count,
    required this.photos,
    this.focus = const {},
    this.place = 0,
  });

  static const _billings = [
    (key: "people_booth", you: "YOUR NO. 1", me: "MY NO. 1"),
    (
      key: "people_booth_2",
      you: "ALWAYS IN THE PICTURE",
      me: "ALWAYS IN THE PICTURE",
    ),
    (
      key: "people_booth_3",
      you: "NEVER OUT OF FRAME",
      me: "NEVER OUT OF FRAME",
    ),
  ];
  static final pageKeys = [for (final billing in _billings) billing.key];

  final RewindFace person;
  final int count;
  final List<EnteFile> photos;
  final Map<EnteFile, Alignment> focus;
  final int place;

  @override
  String get key => _billings[place].key;

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final name = (person.name ?? "").toUpperCase();
    final billing = _billings[place];
    final covered = ModalRoute.of(context)?.isCurrent == false;
    return RewindShareable(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const RewindBackdrop(
            color: Color(0xFF9841E3),
            pattern: RewindStripes(Color(0xFF9D4EE0)),
          ),
          RewindStage(
            children: [
              Positioned.fill(
                child: RewindLeave(
                  position: position,
                  centerY: 330,
                  child: _Booth(
                    photos: photos,
                    focus: focus,
                    active: isActive && !covered,
                  ),
                ),
              ),
              RewindLayer(
                rect: const Rect.fromLTWH(278, 489, 77.8, 76.1),
                position: position,
                child: IgnorePointer(
                  child: RewindEntrance(
                    preset: RewindPreset.bubble,
                    active: isActive,
                    delayMs: _Booth.printedMs,
                    child: Transform.rotate(
                      angle: -7 * pi / 180,
                      child: SvgPicture.file(
                        RewindAssets.file(RewindAssets.heartEyesSmiley),
                      ),
                    ),
                  ),
                ),
              ),
              RewindLayer(
                rect: const Rect.fromLTWH(24, 601, 300, 24),
                position: position,
                child: RewindEntrance(
                  preset: RewindPreset.line,
                  active: isActive,
                  delayMs: 150,
                  child: RewindVoice(
                    you: billing.you,
                    me: billing.me,
                    builder: (text) => Text(
                      text,
                      style: RewindTextStyles.display(20, letterSpacing: 0.3),
                    ),
                  ),
                ),
              ),
              RewindLayer(
                rect: const Rect.fromLTWH(24, 620, 340, 80),
                position: position,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: RewindFitWidth(
                    width: 320,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8, right: 28),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          RewindEntrance(
                            preset: RewindPreset.slap,
                            active: isActive,
                            delayMs: 300,
                            origin: Alignment.centerLeft,
                            child: RewindOutlinedText(
                              name,
                              style: RewindTextStyles.display(
                                74,
                                color: RewindColors.yellow,
                                height: 0.9,
                                letterSpacing: -2.22,
                              ),
                              outline: 4,
                              shadow: const Offset(2.642, 3.171),
                            ),
                          ),
                          Positioned(
                            right: -28,
                            top: -8,
                            width: 42.5,
                            height: 42.5,
                            child: RewindKeyframes(
                              active: isActive,
                              delayMs: 1400,
                              durationMs: 520,
                              curve: const Cubic(0.2, 0.9, 0.3, 1.4),
                              hiddenBeforeStart: true,
                              poses: const [
                                RewindPose(0, scale: 0, turn: -30),
                                RewindPose(0.6, scale: 1.2, turn: 8),
                                RewindPose(1),
                              ],
                              child: SvgPicture.file(
                                RewindAssets.file(RewindAssets.pinkHeart),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              RewindLayer(
                rect: const Rect.fromLTWH(24, 704, 208, 52),
                position: position,
                child: RewindEntrance(
                  preset: RewindPreset.line,
                  active: isActive,
                  delayMs: 450,
                  child: Text(
                    "${rewindCounted(count, "photo", "photos")} this year!",
                    style: RewindTextStyles.body(18),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Booth extends StatefulWidget {
  const _Booth({
    required this.photos,
    required this.focus,
    required this.active,
  });

  static const printedMs = _printStartMs + _printMs;
  static const _printStartMs = 750;
  static const _printMs = 2600;

  final List<EnteFile> photos;
  final Map<EnteFile, Alignment> focus;
  final bool active;

  @override
  State<_Booth> createState() => _BoothState();
}

typedef _Strip = ({
  int print,
  List<EnteFile> photos,
  double offset,
  double angle,
});

typedef _Fall = ({_Strip strip, AnimationController drop});

class _BoothState extends State<_Booth> with TickerProviderStateMixin {
  static const _slot = Rect.fromLTWH(58, 96, 274, 46);
  static const _strip = Rect.fromLTWH(83, 118, 224, 451);
  static const _grabMargin = 12.0;
  static const _grabBelowStrip = 23.0;
  static const _repullGraceMs = 1500;
  static const _stops = [116.0, 226.0, 336.0, 451.0];
  static const _swayMs = 1300;
  static const _nudgeStartMs = _Booth.printedMs + _swayMs + 300;
  static const _nudgeMs = 650;
  static const _hangMs = 5000;
  static const _tugMs = 480;
  static const _tugDistance = 34.0;
  static const _tearDistance = 24.0;
  static const _tearVelocity = 300.0;
  static const _fallDistance = 900.0;
  static const _fallDuration = Duration(milliseconds: 520);
  static const _move = Cubic(0.4, 0, 0.3, 1);
  static const _drop = Cubic(0.2, 0.8, 0.3, 1);

  late final _strips = _stripsOf(widget.photos);
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _nudgeStartMs + _nudgeMs),
  );
  late final _wait = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _hangMs - _tugMs),
  );
  late final _tugging = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _tugMs),
  );
  late final _pull = AnimationController.unbounded(vsync: this);
  final _falls = <_Fall>[];
  var _lastStop = -1;
  var _buzzes = true;
  var _prints = 0;
  var _shown = 0;
  var _drag = 0.0;
  var _holding = false;
  var _still = false;

  static List<List<EnteFile>> _stripsOf(List<EnteFile> photos) {
    const frames = RewindBoothStrip.frames;
    if (photos.length < frames) {
      return [
        [
          for (var i = 0; i < frames && photos.isNotEmpty; i++)
            photos[i % photos.length],
        ],
      ];
    }
    return [
      for (var start = 0; start + frames <= photos.length; start += frames)
        photos.sublist(start, start + frames),
    ];
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onPrinting);
    _wait.addStatusListener((status) {
      if (status.isCompleted) _resumeHang();
    });
    _tugging.addStatusListener((status) {
      if (status.isCompleted) _autoTear();
    });
    if (widget.active) _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(_Booth oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active) {
      _wait.stop();
      _tugging.stop();
      if (_holding) {
        _holding = false;
        _snapBack();
      }
      return;
    }
    if (_controller.isDismissed) _controller.forward();
    _resumeHang();
  }

  @override
  void dispose() {
    _controller.dispose();
    _wait.dispose();
    _tugging.dispose();
    _pull.dispose();
    for (final fall in _falls) {
      fall.drop.dispose();
    }
    super.dispose();
  }

  double get _elapsed =>
      _controller.value * _controller.duration!.inMilliseconds;

  bool get _autoDrops => _strips.length > 1 && !_still;

  double get _tug =>
      _tugDistance * Curves.easeInOutCubic.transform(_tugging.value);

  void _onPrinting() {
    final stop = _printed(_elapsed).stop;
    if (stop > _lastStop) {
      _lastStop = stop;
      if (_buzzes) unawaited(HapticFeedback.lightImpact());
    }
    _resumeHang();
  }

  void _resumeHang() {
    if (!widget.active || _holding || !_autoDrops) return;
    if (_elapsed < _Booth.printedMs) return;
    final step = _wait.isCompleted ? _tugging : _wait;
    if (!step.isAnimating && !step.isCompleted) unawaited(step.forward());
  }

  void _resetHang() {
    _wait.reset();
    _tugging.reset();
  }

  void _autoTear() {
    if (widget.active && !_holding) _tear(byHand: false);
  }

  ({double length, int stop}) _printed(double elapsed) {
    final t = ((elapsed - _Booth._printStartMs) / _Booth._printMs).clamp(
      0.0,
      1.0,
    );
    final span = t * _stops.length;
    final index = min(span.floor(), _stops.length - 1);
    final within = span - index;
    final from = index == 0 ? 0.0 : _stops[index - 1];
    final moving = (within / 0.66).clamp(0.0, 1.0);
    final length = from + (_stops[index] - from) * _move.transform(moving);
    return (length: length, stop: moving >= 1 ? index : index - 1);
  }

  bool _canPullAt(Offset position) {
    if (!_still && _elapsed < _Booth._printStartMs) return false;
    final hanging = _hanging(_still ? double.infinity : _elapsed);
    final reach = _justTorn ? max(0.0, hanging.offset) : hanging.offset;
    return Rect.fromLTRB(
      _slot.left - _grabMargin,
      _slot.top - _grabMargin,
      _slot.right + _grabMargin,
      _strip.bottom + reach + _grabBelowStrip,
    ).contains(position);
  }

  bool get _justTorn =>
      _prints > 0 && _elapsed < _Booth._printStartMs + _repullGraceMs;

  void _startPull(DragStartDetails details) {
    _holding = true;
    _pull.stop();
    _drag = max(0.0, _pull.value) + _tug;
    _resetHang();
    _pull.value = _drag;
  }

  void _updatePull(DragUpdateDetails details) {
    _drag += details.primaryDelta ?? 0;
    _pull.value = max(0.0, _drag);
  }

  void _endPull(DragEndDetails details) {
    _holding = false;
    final velocity = details.primaryVelocity ?? 0;
    if (_pull.value >= _tearDistance || velocity >= _tearVelocity) {
      _tear(byHand: true);
    } else {
      _snapBack();
    }
  }

  void _cancelPull() {
    if (!_holding) return;
    _holding = false;
    _snapBack();
  }

  void _snapBack() {
    unawaited(
      _pull.animateTo(
        0,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutBack,
      ),
    );
    _resumeHang();
  }

  void _tear({required bool byHand}) {
    if (byHand) unawaited(HapticFeedback.mediumImpact());
    final elapsed = _still ? double.infinity : _elapsed;
    final torn = _hanging(elapsed);
    setState(() {
      _prints++;
      _shown = (_shown + 1) % _strips.length;
    });
    _pull.stop();
    _pull.value = 0;
    _resetHang();
    _lastStop = -1;
    _buzzes = byHand;
    if (_still) return;
    _letFall(torn);
    unawaited(
      _controller.forward(
        from: _Booth._printStartMs / _controller.duration!.inMilliseconds,
      ),
    );
  }

  void _letFall(_Strip strip) {
    final fall = (
      strip: strip,
      drop: AnimationController(vsync: this, duration: _fallDuration),
    );
    setState(() => _falls.add(fall));
    unawaited(
      fall.drop.forward().then((_) {
        if (!mounted) return;
        setState(() => _falls.remove(fall));
        fall.drop.dispose();
      }),
    );
  }

  _Strip _hanging(double elapsed) => (
    print: _prints,
    photos: _strips[_shown],
    offset: _hangingOffset(elapsed),
    angle: _sway(elapsed - _Booth.printedMs),
  );

  double _hangingOffset(double elapsed) {
    final length = _still ? _strip.height : _printed(elapsed).length;
    final nudge = _nudge(elapsed - _nudgeStartMs);
    return length - _strip.height + _pull.value + _tug + nudge;
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _PullDownRecognizer:
            GestureRecognizerFactoryWithHandlers<_PullDownRecognizer>(
              () =>
                  _PullDownRecognizer(canPullAt: _canPullAt, debugOwner: this),
              (recognizer) => recognizer
                ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context)
                ..dragStartBehavior = DragStartBehavior.down
                ..onStart = widget.active ? _startPull : null
                ..onUpdate = widget.active ? _updatePull : null
                ..onEnd = widget.active ? _endPull : null
                ..onCancel = widget.active ? _cancelPull : null,
            ),
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _controller,
          _tugging,
          _pull,
          for (final fall in _falls) fall.drop,
        ]),
        builder: (context, _) {
          final capturing = RewindShareable.capturing(context);
          final still = _still || capturing;
          final elapsed = still ? double.infinity : _elapsed;
          final printing =
              elapsed > _Booth._printStartMs && elapsed < _Booth.printedMs;
          final jitter = printing
              ? ((elapsed / 90).floor().isEven ? 0.7 : -0.7)
              : 0.0;
          final drop = _drop.transform(((elapsed - 150) / 520).clamp(0.0, 1.0));
          final slotOffset = Offset(jitter, still ? 0 : _slotDrop(drop));
          final slotOpacity = still ? 1.0 : (drop / 0.7).clamp(0.0, 1.0);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fromRect(
                rect: _slot.shift(slotOffset),
                child: Opacity(opacity: slotOpacity, child: const _SlotBody()),
              ),
              Positioned(
                left: 0,
                top: _strip.top,
                width: RewindStage.size.width,
                height: RewindStage.size.height * 2,
                child: ClipRect(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: capturing
                        ? _captured()
                        : [
                            _positioned(_hanging(elapsed)),
                            for (final fall in _falls) _falling(fall),
                          ],
                  ),
                ),
              ),
              Positioned.fromRect(
                rect: Rect.fromLTWH(
                  _slot.left,
                  _slot.top,
                  _slot.width,
                  28,
                ).shift(slotOffset),
                child: Opacity(opacity: slotOpacity, child: const _SlotLip()),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _captured() {
    final shown = _falls.lastOrNull?.strip.print ?? _prints;
    final strips = [
      (print: _prints, photos: _strips[_shown], offset: 0.0, angle: 0.0),
      for (final fall in _falls)
        (
          print: fall.strip.print,
          photos: fall.strip.photos,
          offset: 0.0,
          angle: 0.0,
        ),
    ];
    return [
      for (final strip in strips)
        _positioned(strip, visible: strip.print == shown),
    ];
  }

  Widget _falling(_Fall fall) {
    final t = Curves.easeIn.transform(fall.drop.value);
    return _positioned((
      print: fall.strip.print,
      photos: fall.strip.photos,
      offset: fall.strip.offset + _fallDistance * t,
      angle: fall.strip.angle + 7 * t,
    ));
  }

  Widget _positioned(_Strip strip, {bool visible = true}) {
    return Positioned(
      key: ValueKey(strip.print),
      left: _strip.left,
      top: 0,
      child: Offstage(
        offstage: !visible,
        child: Transform.translate(
          offset: Offset(0, strip.offset),
          child: Transform.rotate(
            angle: strip.angle * pi / 180,
            alignment: Alignment.topCenter,
            child: _printedStrip(strip.photos),
          ),
        ),
      ),
    );
  }

  Widget _printedStrip(List<EnteFile> photos) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 8,
            offset: Offset(-2, 4),
          ),
        ],
      ),
      child: RewindBoothStrip(
        photos: [for (final photo in photos) _photo(photo)],
      ),
    );
  }

  Widget _photo(EnteFile file) =>
      RewindPhoto(file, focus: widget.focus[file] ?? Alignment.center);

  double _slotDrop(double t) {
    if (t < 0.7) return -90 + 94 * t / 0.7;
    return 4 - 4 * (t - 0.7) / 0.3;
  }

  double _sway(double sinceMs) {
    if (sinceMs <= 0 || sinceMs >= _swayMs) return 0;
    final t = Curves.easeOut.transform(sinceMs / _swayMs);
    const angles = [0.0, 1.4, -0.8, 0.0];
    final span = t * (angles.length - 1);
    final i = min(span.floor(), angles.length - 2);
    return angles[i] + (angles[i + 1] - angles[i]) * (span - i);
  }

  double _nudge(double sinceMs) {
    if (sinceMs <= 0 || sinceMs >= _nudgeMs) return 0;
    return 16 * sin(pi * Curves.easeOut.transform(sinceMs / _nudgeMs));
  }
}

class _PullDownRecognizer extends VerticalDragGestureRecognizer {
  _PullDownRecognizer({required this.canPullAt, super.debugOwner});

  static const _claimDistance = 6.0;

  final bool Function(Offset position) canPullAt;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      canPullAt(event.localPosition) && super.isPointerAllowed(event);

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) => globalDistanceMoved > _claimDistance;
}

class _SlotBody extends StatelessWidget {
  const _SlotBody();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: RewindColors.ink,
          width: 3,
          strokeAlign: BorderSide.strokeAlignOutside,
        ),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF6F5F2), Color(0xFFDCDAD5)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x42000000),
            offset: Offset(0, 14),
            blurRadius: 26,
          ),
          BoxShadow(color: Color(0x14000000), offset: Offset(0, 3)),
        ],
      ),
      child: const Padding(
        padding: EdgeInsets.fromLTRB(37, 18, 37, 18),
        child: _Slit(),
      ),
    );
  }
}

class _SlotLip extends StatelessWidget {
  const _SlotLip();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF6F5F2), Color(0xFFE9E7E3)],
        ),
      ),
      child: const Padding(
        padding: EdgeInsets.fromLTRB(20.9, 18, 20.9, 0),
        child: _Slit(),
      ),
    );
  }
}

class _Slit extends StatelessWidget {
  const _Slit();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF000000), Color(0xFF161616)],
          stops: [0, 0.5],
        ),
      ),
      child: const SizedBox(height: 10),
    );
  }
}
