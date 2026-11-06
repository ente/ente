import "dart:async";
import "dart:math";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_svg/flutter_svg.dart";
import "package:photos/models/file/file.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_confetti.dart";
import "package:photos/ui/rewind/widgets/rewind_count_up.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_keyframes.dart";
import "package:photos/ui/rewind/widgets/rewind_numbers.dart";
import "package:photos/ui/rewind/widgets/rewind_photo.dart";
import "package:photos/ui/rewind/widgets/rewind_photo_frames.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_swap_in.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";
import "package:photos/ui/rewind/widgets/rewind_wave.dart";

typedef PlaceStamp = ({rust.RewindCity city, EnteFile? photo});

class PlacesQuizPage extends RewindPage {
  PlacesQuizPage(this.places, this.stamps)
    : _board = _shuffledBoard(stamps.map((stamp) => stamp.city.name));

  static const pageKey = "places";

  final rust.Places places;
  final List<PlaceStamp> stamps;
  final List<_Slot> _board;
  int? _guess;

  @override
  String get key => pageKey;

  static List<_Slot> _shuffledBoard(Iterable<String> names) {
    final count = min(names.length, _Slot.fillOrder.length);
    final slots = [
      for (final index in _Slot.fillOrder.take(count)) _Slot.board[index],
    ];
    return slots..shuffle(Random(names.join("|").hashCode));
  }

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    return _PlacesQuiz(page: this, position: position, isActive: isActive);
  }
}

class _Slot {
  const _Slot(
    this.center, {
    this.portrait = false,
    this.turn = 0,
    this.scale = 1,
  });

  static const board = [
    _Slot(Offset(101.1, 330), portrait: true),
    _Slot(Offset(104.2, 497), turn: 3.04),
    _Slot(Offset(101.2, 619)),
    _Slot(Offset(288.2, 288), turn: -1.67),
    _Slot(Offset(289.1, 453), portrait: true),
    _Slot(Offset(287.2, 619), turn: -2.09),
  ];
  static const fillOrder = [0, 3, 4, 1, 5, 2];
  static const podium = [
    _Slot(Offset(195, 408.7), portrait: true, scale: 1.018),
    _Slot(Offset(106, 632), portrait: true, scale: 0.8),
    _Slot(Offset(284, 634), turn: -1.67, scale: 0.92),
  ];

  final Offset center;
  final bool portrait;
  final double turn;
  final double scale;

  Size get size =>
      (portrait ? const Size(139.5, 184) : const Size(139.6, 93.9)) * scale;

  Rect get rect =>
      Rect.fromCenter(center: center, width: size.width, height: size.height);
}

enum _Phase { pick, picked, reveal, done }

class _PlacesQuiz extends StatefulWidget {
  const _PlacesQuiz({
    required this.page,
    required this.position,
    required this.isActive,
  });

  final PlacesQuizPage page;
  final double position;
  final bool isActive;

  @override
  State<_PlacesQuiz> createState() => _PlacesQuizState();
}

class _PlacesQuizState extends State<_PlacesQuiz> {
  static const _background = Color(0xFF3F78F0);
  static const _stripes = Color(0xFF4A82F5);
  static const _revealMs = 1250;
  static const _rankMs = 600;
  static const _rankGapMs = 330;
  static const _crownMs = _rankMs + 3 * _rankGapMs + 700;
  static const _doneMs = _rankMs + 3 * _rankGapMs + 1300;

  late var _phase = widget.page._guess == null ? _Phase.pick : _Phase.done;
  late final _replayed = _phase == _Phase.done;
  final _timers = <Timer>[];
  Timer? _invite;
  var _wiggles = 0;
  var _wiggling = -1;

  List<PlaceStamp> get _stamps => widget.page.stamps;

  List<_Slot> get _board => widget.page._board;

  int? get _guess => widget.page._guess;

  @override
  void initState() {
    super.initState();
    _syncInvite();
  }

  @override
  void didUpdateWidget(_PlacesQuiz oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncInvite();
  }

  @override
  void dispose() {
    _invite?.cancel();
    for (final timer in _timers) {
      timer.cancel();
    }
    super.dispose();
  }

  void _syncInvite() {
    final inviting = widget.isActive && _phase == _Phase.pick;
    if (!inviting) {
      _invite?.cancel();
      _invite = null;
    } else {
      _invite ??= Timer.periodic(const Duration(milliseconds: 1500), (_) {
        setState(() {
          _wiggles++;
          _wiggling = Random().nextInt(_stamps.length);
        });
      });
    }
  }

  void _later(int ms, VoidCallback callback) {
    _timers.add(
      Timer(Duration(milliseconds: ms), () {
        if (mounted) callback();
      }),
    );
  }

  void _pick(int rank) {
    if (_phase != _Phase.pick) return;
    unawaited(HapticFeedback.selectionClick());
    widget.page._guess = rank;
    setState(() => _phase = _Phase.picked);
    _syncInvite();
    _later(_revealMs, () => setState(() => _phase = _Phase.reveal));
    _later(_revealMs + _crownMs + 370, () {
      unawaited(
        rank == 0
            ? HapticFeedback.mediumImpact()
            : HapticFeedback.lightImpact(),
      );
    });
    _later(_revealMs + _doneMs, () => setState(() => _phase = _Phase.done));
  }

  @override
  Widget build(BuildContext context) {
    final revealed = _phase == _Phase.reveal || _phase == _Phase.done;
    final podium = RewindStage(children: _podium(revealed));
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
            if (_replayed)
              MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: podium,
              )
            else ...[
              RewindStage(children: _boardLayers()),
              RewindWaveReveal(
                active: revealed,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const RewindBackdrop(
                      color: _background,
                      pattern: RewindStripes(_stripes),
                    ),
                    podium,
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _leave(double centerY, Widget child) =>
      RewindLeave(position: widget.position, centerY: centerY, child: child);

  List<Widget> _boardLayers() {
    final picked = _guess;
    final order = [
      for (var rank = 0; rank < _board.length; rank++)
        if (rank != picked) rank,
      ?picked,
    ];
    return [
      Positioned(
        left: 0,
        right: 0,
        top: 160,
        child: _leave(
          190,
          AnimatedOpacity(
            opacity: _phase == _Phase.pick ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            child: RewindEntrance(
              preset: RewindPreset.line,
              active: widget.isActive,
              child: Column(
                children: [
                  Text(
                    "WHERE DID YOU SHOOT MOST?",
                    textAlign: TextAlign.center,
                    style: RewindTextStyles.display(
                      20,
                      color: RewindColors.white,
                      height: 1.1,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    "Make a guess 👀",
                    textAlign: TextAlign.center,
                    style: RewindTextStyles.body(17, height: 1.2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      if (picked != null)
        Positioned(
          left: 41,
          top: 132,
          width: 316,
          child: _leave(
            150,
            RewindSwapIn(
              text: _stamps[picked].city.name,
              alignment: Alignment.centerLeft,
              child: Text(
                "${_stamps[picked].city.name}? Let’s check\nthe postmarks.",
                style: RewindTextStyles.body(19, height: 1.15),
              ),
            ),
          ),
        ),
      for (final rank in order) _boardStamp(rank),
    ];
  }

  Widget _boardStamp(int rank) {
    final slot = _board[rank];
    final size = slot.size;
    final picked = _guess == rank;
    final dimmed = _guess != null && !picked;
    final fill = _Slot.fillOrder.indexOf(_Slot.board.indexOf(slot));
    return Positioned(
      key: ValueKey(rank),
      left: slot.center.dx - size.width / 2,
      top: slot.center.dy - size.height / 2,
      width: size.width,
      height: size.height,
      child: _leave(
        slot.center.dy,
        AnimatedOpacity(
          opacity: dimmed ? 0.45 : 1,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOut,
          child: RewindKeyframes(
            active: widget.isActive,
            delayMs: 150 + 120 * fill,
            durationMs: 650,
            curve: const Cubic(0.2, 0.8, 0.3, 1),
            hiddenBeforeStart: true,
            poses: const [
              RewindPose(0, dy: -90, turn: -14, scale: 1.1, opacity: 0),
              RewindPose(0.7, dy: 6, turn: 2),
              RewindPose(1),
            ],
            child: RewindKeyframes(
              active: _wiggling == rank,
              replay: _wiggling == rank ? _wiggles : null,
              durationMs: 560,
              curve: Curves.easeInOut,
              poses: const [
                RewindPose(0),
                RewindPose(0.33, dy: -6, turn: -3),
                RewindPose(0.66, turn: 2),
                RewindPose(1),
              ],
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _phase == _Phase.pick ? () => _pick(rank) : null,
                child: RewindKeyframes(
                  active: picked,
                  durationMs: 420,
                  curve: const Cubic(0.2, 0.9, 0.3, 1.3),
                  poses: [
                    const RewindPose(0),
                    RewindPose(
                      0.5,
                      dy: -14,
                      scale: 1.12,
                      turn: (4 - slot.turn) / 2,
                    ),
                    RewindPose(1, dy: -6, scale: 1.08, turn: 4 - slot.turn),
                  ],
                  child: Transform.rotate(
                    angle: slot.turn * pi / 180,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: picked ? 8 : 4),
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeOut,
                      builder: (context, lift, _) =>
                          _stamp(rank, slot, size, lift),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stamp(int rank, _Slot slot, Size size, double lift) {
    final photo = _stamps[rank].photo;
    return SizedBox.fromSize(
      size: size,
      child: RewindStamp(
        photo: photo == null
            ? const ColoredBox(color: Color(0xFFD9D9D9))
            : RewindPhoto(photo, placeholder: const Color(0xFFD9D9D9)),
        label: _stamps[rank].city.name,
        portrait: slot.portrait,
        width: size.width,
        lift: lift * 139.6 / size.width,
      ),
    );
  }

  List<Widget> _podium(bool revealed) {
    final guess = _guess;
    final podium = [
      for (var rank = 0; rank < min(3, _stamps.length); rank++)
        _Slot.podium[rank].rect,
    ];
    return [
      for (var rank = podium.length - 1; rank >= 0; rank--)
        _podiumStamp(rank, podium[rank], revealed),
      for (var rank = podium.length - 1; rank >= 0; rank--) ...[
        _rankBadge(rank, podium[rank], revealed),
        _countPill(rank, podium[rank], revealed),
      ],
      if (podium.isNotEmpty) _crown(podium.first, revealed),
      ..._head(revealed),
      if (guess == 0 && !_replayed)
        Positioned.fill(
          child: RewindConfetti(count: 70, active: revealed, delayMs: _crownMs),
        ),
    ];
  }

  int _rankDelay(int rank) => _rankMs + (2 - rank) * _rankGapMs;

  Widget _podiumStamp(int rank, Rect rect, bool revealed) {
    final slot = _Slot.podium[rank];
    return Positioned.fromRect(
      rect: rect,
      child: _leave(
        rect.center.dy,
        RewindKeyframes(
          active: revealed,
          delayMs: 140 + 60 * rank,
          durationMs: 760,
          curve: const Cubic(0.2, 0.9, 0.3, 1.25),
          poses: const [RewindPose(0, scale: 1.14, turn: -4), RewindPose(1)],
          child: Transform.rotate(
            angle: slot.turn * pi / 180,
            child: _stamp(rank, slot, rect.size, 4),
          ),
        ),
      ),
    );
  }

  Widget _rankBadge(int rank, Rect rect, bool revealed) {
    final first = rank == 0;
    final size = first ? 44.09 : 40.0;
    return Positioned.fromRect(
      rect: Rect.fromCenter(
        center:
            rect.topLeft +
            (first ? const Offset(8.8, 8.8) : const Offset(8, 8)),
        width: size,
        height: size,
      ),
      child: _leave(
        rect.top,
        RewindKeyframes(
          active: revealed,
          delayMs: _rankDelay(rank),
          durationMs: 420,
          curve: const Cubic(0.3, 0.6, 0.4, 1),
          hiddenBeforeStart: true,
          poses: const [
            RewindPose(0, scale: 2.4, turn: -30, opacity: 0),
            RewindPose(0.55, scale: 0.9, turn: -4),
            RewindPose(1, turn: -6),
          ],
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: RewindColors.ink,
              shape: BoxShape.circle,
              border: Border.all(
                color: RewindColors.cream,
                width: first ? 3.86 : 3.5,
              ),
            ),
            child: Center(
              child: Text(
                "${rank + 1}",
                style: RewindTextStyles.display(first ? 24.25 : 22),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _countPill(int rank, Rect rect, bool revealed) {
    final first = rank == 0;
    final count = _stamps[rank].city.photoCount;
    final delay = _rankDelay(rank) + 120;
    return Positioned(
      left: rect.center.dx - 100,
      width: 200,
      top: rect.bottom - 7,
      child: _leave(
        rect.bottom,
        Center(
          child: RewindKeyframes(
            active: revealed,
            delayMs: delay,
            durationMs: 420,
            curve: const Cubic(0.2, 0.9, 0.3, 1.3),
            hiddenBeforeStart: true,
            poses: const [
              RewindPose(0, scale: 0),
              RewindPose(0.6, scale: 1.1),
              RewindPose(1),
            ],
            child: Container(
              padding: first
                  ? const EdgeInsets.fromLTRB(12.1, 7.7, 12.1, 6.6)
                  : const EdgeInsets.fromLTRB(11, 7, 11, 6),
              decoration: BoxDecoration(
                color: RewindColors.ink,
                borderRadius: BorderRadius.circular(99),
              ),
              child: RewindCountUp(
                value: count,
                active: revealed,
                delayMs: delay,
                durationMs: 700,
                builder: (context, text) => Text(
                  "$text ${count == 1 ? "photo" : "photos"}",
                  style: RewindTextStyles.body(first ? 15.43 : 14, height: 1.2)
                      .copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _crown(Rect winner, bool revealed) {
    const size = Size(81.567, 64.73);
    return Positioned.fromRect(
      rect: Rect.fromCenter(
        center: winner.topRight + const Offset(-6, -11),
        width: size.width,
        height: size.height,
      ),
      child: _leave(
        winner.top,
        RewindKeyframes(
          active: revealed,
          delayMs: _crownMs,
          durationMs: 620,
          curve: const Cubic(0.2, 0.9, 0.3, 1.4),
          hiddenBeforeStart: true,
          poses: const [
            RewindPose(0, dy: -70, scale: 0.4, opacity: 0),
            RewindPose(0.6, dy: 4, scale: 1.2, turn: 32),
            RewindPose(1, turn: 25.6),
          ],
          child: SvgPicture.file(RewindAssets.file(RewindAssets.crown)),
        ),
      ),
    );
  }

  List<Widget> _head(bool revealed) {
    final places = widget.page.places;
    final travelled = places.distanceKm > 0;
    final winner = _stamps.first.city;
    Widget swap(Widget child) => RewindKeyframes(
      active: revealed,
      delayMs: 250,
      durationMs: 320,
      curve: const Cubic(0.2, 0.9, 0.3, 1.25),
      hiddenBeforeStart: true,
      origin: Alignment.centerLeft,
      poses: const [
        RewindPose(0, dy: 10, scale: 0.94, opacity: 0),
        RewindPose(1),
      ],
      child: child,
    );
    return [
      Positioned(
        left: 38,
        top: 106,
        child: _leave(
          110,
          swap(
            Text(
              travelled ? "YOUR PHOTOS TRAVELLED" : "YOUR TOP PLACE",
              style: RewindTextStyles.display(17, letterSpacing: 0.3),
            ),
          ),
        ),
      ),
      Positioned(
        left: 39,
        top: 133,
        child: _leave(
          160,
          swap(
            RewindFitWidth(
              width: 330,
              child: RewindOutlinedText(
                travelled
                    ? "${rewindCount(places.distanceKm)} KM"
                    : winner.name.toUpperCase(),
                style: RewindTextStyles.display(
                  71.872,
                  color: RewindColors.yellow,
                  height: 0.84,
                  letterSpacing: -2.156,
                ),
                outline: 3,
                shadow: const Offset(2.642, 3.171),
              ),
            ),
          ),
        ),
      ),
      Positioned(
        left: 38,
        top: 199,
        width: 330,
        child: _leave(220, swap(Text(_verdict(), style: _line))),
      ),
    ];
  }

  TextStyle get _line => RewindTextStyles.body(17, height: 1.32);

  String _verdict() {
    final guess = _guess ?? 0;
    final cities = [for (final stamp in _stamps) stamp.city];
    final winner = cities.first;
    final winning = rewindCounted(winner.photoCount, "photo", "photos");
    if (guess == 0) {
      final next = cities.skip(1).take(2).map((city) => city.name).toList();
      return switch (next.length) {
        0 => "${winner.name} won with $winning.",
        1 => "${winner.name} won with $winning. ${next[0]} came next.",
        _ =>
          "${winner.name} won with $winning. "
              "${next[0]} and ${next[1]} came next.",
      };
    }
    final pick = cities[guess];
    if (guess < 3) {
      return "${pick.name} came ${guess == 1 ? "2nd" : "3rd"}. "
          "${winner.name} won with $winning.";
    }
    return "${pick.name} had ${rewindCount(pick.photoCount)}. "
        "${winner.name} ran away with ${rewindCount(winner.photoCount)}.";
  }
}
