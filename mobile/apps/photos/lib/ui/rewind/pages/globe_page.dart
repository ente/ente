import "dart:math";
import "dart:typed_data";
import "dart:ui" as ui;

import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter/scheduler.dart";
import "package:flutter/services.dart";
import "package:photos/models/file/file.dart";
import "package:photos/src/rust/api/rewind_api.dart" as rust;
import "package:photos/ui/rewind/shell/rewind_page.dart";
import "package:photos/ui/rewind/shell/rewind_page_scope.dart";
import "package:photos/ui/rewind/shell/rewind_share.dart";
import "package:photos/ui/rewind/theme/rewind_assets.dart";
import "package:photos/ui/rewind/theme/rewind_colors.dart";
import "package:photos/ui/rewind/theme/rewind_text_styles.dart";
import "package:photos/ui/rewind/widgets/rewind_backdrop.dart";
import "package:photos/ui/rewind/widgets/rewind_count_up.dart";
import "package:photos/ui/rewind/widgets/rewind_entrance.dart";
import "package:photos/ui/rewind/widgets/rewind_hint.dart";
import "package:photos/ui/rewind/widgets/rewind_numbers.dart";
import "package:photos/ui/rewind/widgets/rewind_pixels.dart";
import "package:photos/ui/rewind/widgets/rewind_reveal_layer.dart";
import "package:photos/ui/rewind/widgets/rewind_stage.dart";
import "package:photos/ui/rewind/widgets/rewind_text.dart";

class GlobePage extends RewindPage {
  GlobePage(
    this.globe,
    this.photos, {
    this.photo = rewindPhoto,
    this.bytes = rewindThumbnailBytes,
  });

  static const pageKey = "globe";
  static const earthKm = 40075;
  static const _reelJourneyMs = 2800.0;

  static const _space = Color(0xFF1C1B66);
  static const _spaceRay = Color(0xFF222174);

  final rust.Globe globe;
  final List<EnteFile?> photos;
  final RewindPhotoBuilder photo;
  final RewindBytes bytes;

  late final _World _world = _World.of(globe);

  late final RewindWarm<RewindDecoded> _pins = RewindDecoded.warm([
    for (final place in _GlobeViewState.docked(_world, globe, photos))
      photos[place]!,
  ], bytes);

  @override
  String get key => pageKey;

  double get _reelJourney => min(_world.journeyMs, _reelJourneyMs);

  @override
  Duration? get reelHold => Duration(milliseconds: 1450 + _reelJourney.round());

  @override
  Future<bool> warmUp() async {
    await _pins.value;
    return true;
  }

  @override
  void release() => _pins.release();

  @override
  Widget build(
    BuildContext context,
    double position, {
    required bool isActive,
  }) {
    final km = globe.distanceKm;
    final lap = km >= earthKm
        ? "That’s ${(km / earthKm).toStringAsFixed(1)} times around the Earth."
        : "That’s ${max(1, (100 * km / earthKm).round())}% of the way "
              "around the Earth.";
    return Stack(
      fit: StackFit.expand,
      children: [
        _card(
          position,
          isActive,
          km,
          lap,
          RewindPageScope.reelOf(context) ? _reelJourney : _world.journeyMs,
        ),
        RewindHint(
          "DRAG TO SPIN",
          centerY: 540,
          active: isActive,
          position: position,
          delayMs: 2800,
        ),
      ],
    );
  }

  Widget _card(
    double position,
    bool isActive,
    int km,
    String body,
    double journeyMs,
  ) {
    return RewindWarmBuilder<RewindDecoded>(
      warm: _pins,
      builder: (context, pins) => RewindShareable(
        enabled: pins != null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const RewindBackdrop(
              color: _space,
              pattern: RewindRays(
                _spaceRay,
                center: _GlobeView.center,
                wedge: 7.5,
                step: 15,
              ),
            ),
            Semantics(
              label: "Your photos flew ${rewindCount(km)} kilometres. $body",
              child: ExcludeSemantics(
                child: RewindStage(
                  children: [
                    Positioned.fill(
                      child: RewindLeave(
                        position: position,
                        centerY: _GlobeView.center.dy,
                        child: _GlobeView(
                          world: _world,
                          globe: globe,
                          photos: photos,
                          photo: photo,
                          pins: pins,
                          active: isActive,
                        ),
                      ),
                    ),
                    RewindRevealLayer(
                      left: 28,
                      top: 597,
                      maxWidth: 316,
                      height: 18,
                      position: position,
                      active: isActive,
                      delayMs: 500,
                      child: RewindVoice(
                        you: "YOUR PHOTOS FLEW",
                        me: "MY PHOTOS FLEW",
                        builder: (text) => Text(
                          text,
                          style: RewindTextStyles.display(17, height: 1.05),
                        ),
                      ),
                    ),
                    RewindRevealLayer(
                      left: 28,
                      top: 622,
                      height: 52,
                      position: position,
                      active: isActive,
                      preset: RewindPreset.slap,
                      delayMs: 700,
                      origin: Alignment.centerLeft,
                      child: RewindFitWidth(
                        width: 322,
                        child: RewindCountUp(
                          value: km,
                          active: isActive,
                          delayMs: _World.introMs.round(),
                          durationMs: journeyMs.round(),
                          builder: (context, text) => RewindOutlinedText(
                            "$text KM",
                            style: RewindTextStyles.display(
                              58,
                              color: RewindColors.yellow,
                              height: 0.84,
                            ),
                            shadow: const Offset(2.2, 2.6),
                          ),
                        ),
                      ),
                    ),
                    RewindRevealLayer(
                      left: 28,
                      top: 688,
                      width: 334,
                      height: 44,
                      position: position,
                      active: isActive,
                      delayMs: 1000,
                      child: Text(body, style: RewindTextStyles.body(17)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

typedef _Vector = ({double x, double y, double z});

_Vector _vector(double latitude, double longitude) {
  final phi = latitude * pi / 180;
  final lambda = longitude * pi / 180;
  return (x: cos(phi) * sin(lambda), y: sin(phi), z: cos(phi) * cos(lambda));
}

_Vector _between(_Vector from, _Vector to, double t) {
  final dot = (from.x * to.x + from.y * to.y + from.z * to.z).clamp(-1.0, 1.0);
  final angle = acos(dot);
  if (angle < 1e-4) return from;
  final a = sin((1 - t) * angle) / sin(angle);
  final b = sin(t * angle) / sin(angle);
  return (
    x: a * from.x + b * to.x,
    y: a * from.y + b * to.y,
    z: a * from.z + b * to.z,
  );
}

double _angle(_Vector from, _Vector to) =>
    acos((from.x * to.x + from.y * to.y + from.z * to.z).clamp(-1.0, 1.0));

class _Leg {
  const _Leg(this.from, this.to, this.startMs, this.flightMs, this.angle);

  final int from;
  final int to;
  final double startMs;
  final double flightMs;
  final double angle;
}

class _Visit {
  _Visit(this.place, this.stops);

  final int place;
  final List<int> stops;
  final List<int> detours = [];
}

class _World {
  const _World({
    required this.land,
    required this.visited,
    required this.places,
    required this.legs,
    required this.landings,
    required this.pinnedMs,
    required this.journeyMs,
    required this.home,
  });

  static const introMs = 1100.0;
  static const _local = 0.035;
  static const _dwellMs = 320.0;
  static const _pinGapMs = 110.0;
  static const _longestJourneyMs = 14000.0;
  static const _tightestPace = 0.7;

  final Float32List land;
  final Uint8List visited;
  final List<_Vector> places;
  final List<_Leg> legs;
  final List<int> landings;
  final List<double> pinnedMs;
  final double journeyMs;
  final _Vector home;

  static _World of(rust.Globe globe) {
    final dots = <double>[];
    final visited = <int>[];
    var dot = 0;
    bool bit(Uint8List bits, int at) => bits[at >> 3] & (1 << (at & 7)) != 0;
    for (final (row, count) in globe.rows.indexed) {
      final latitude = -90 + (row + 0.5) * 180 / globe.rows.length;
      for (var column = 0; column < count; column++, dot++) {
        if (!bit(globe.land, dot)) continue;
        final point = _vector(latitude, -180 + (column + 0.5) * 360 / count);
        dots
          ..add(point.x)
          ..add(point.y)
          ..add(point.z);
        visited.add(bit(globe.visited, dot) ? 1 : 0);
      }
    }
    final places = [
      for (final place in globe.places)
        _vector(
          place.latitudeMicrodegrees / 1e6,
          place.longitudeMicrodegrees / 1e6,
        ),
    ];
    final List<int> route = globe.route;
    var visits = _itinerary(route, places, _local);
    if (visits.length < 2) visits = _itinerary(route, places, 0);
    int landing(_Visit visit) => visit.stops.reduce(
      (a, b) => globe.places[b].photoCount > globe.places[a].photoCount ? b : a,
    );
    var plan = _schedule(visits, places);
    while (visits.length > 2 &&
        plan.clock - introMs > _longestJourneyMs / _tightestPace) {
      _skipSmallest(visits, (visit) => globe.places[landing(visit)].photoCount);
      plan = _schedule(visits, places);
    }
    final pace = min(1.0, _longestJourneyMs / max(1.0, plan.clock - introMs));
    double paced(double ms) =>
        ms <= introMs ? ms : introMs + (ms - introMs) * pace;
    final endMs = paced(plan.clock);

    var sum = (x: 0.0, y: 0.0, z: 0.0);
    for (final stop in route) {
      final place = places[stop];
      sum = (x: sum.x + place.x, y: sum.y + place.y, z: sum.z + place.z);
    }
    final length = sqrt(sum.x * sum.x + sum.y * sum.y + sum.z * sum.z);
    return _World(
      land: Float32List.fromList(dots),
      visited: Uint8List.fromList(visited),
      places: places,
      legs: [
        for (final leg in plan.legs)
          _Leg(
            leg.from,
            leg.to,
            paced(leg.startMs),
            leg.flightMs * pace,
            leg.angle,
          ),
      ],
      landings: [for (final visit in visits) landing(visit)],
      pinnedMs: [
        for (final ms in plan.pinnedMs) ms.isFinite ? paced(ms) : endMs,
      ],
      journeyMs: endMs - introMs,
      home: length < 1e-6
          ? places[route.first]
          : (x: sum.x / length, y: sum.y / length, z: sum.z / length),
    );
  }

  static ({List<_Leg> legs, List<double> pinnedMs, double clock}) _schedule(
    List<_Visit> visits,
    List<_Vector> places,
  ) {
    final pinnedMs = List.filled(places.length, double.infinity);
    double drop(_Visit visit, double from) {
      var at = from;
      for (final stop in [...visit.stops, ...visit.detours]) {
        if (pinnedMs[stop].isFinite) continue;
        pinnedMs[stop] = at;
        at += _pinGapMs;
      }
      return at;
    }

    final legs = <_Leg>[];
    var clock = max(introMs, drop(visits.first, introMs * 0.6));
    for (var visit = 1; visit < visits.length; visit++) {
      final from = visits[visit - 1].place;
      final to = visits[visit].place;
      final angle = _angle(places[from], places[to]);
      final flightMs = 620 + 900 * sqrt(min(1, angle / 1.2));
      legs.add(_Leg(from, to, clock, flightMs, angle));
      clock += flightMs;
      clock = max(clock + _dwellMs, drop(visits[visit], clock));
    }
    return (legs: legs, pinnedMs: pinnedMs, clock: clock);
  }

  static void _skipSmallest(
    List<_Visit> visits,
    int Function(_Visit visit) photos,
  ) {
    var smallest = 1;
    for (var visit = 2; visit < visits.length; visit++) {
      if (photos(visits[visit]) <= photos(visits[smallest])) smallest = visit;
    }
    final skipped = visits.removeAt(smallest);
    final before = visits[smallest - 1];
    before.detours
      ..addAll(skipped.stops)
      ..addAll(skipped.detours);
    if (smallest < visits.length && visits[smallest].place == before.place) {
      final again = visits.removeAt(smallest);
      before.stops.addAll(again.stops);
      before.detours.addAll(again.detours);
    }
  }

  static List<_Visit> _itinerary(
    List<int> route,
    List<_Vector> places,
    double local,
  ) {
    final hubs = <int>[];
    final hubOf = <int, int>{};
    for (final stop in route) {
      hubOf.putIfAbsent(stop, () {
        for (final hub in hubs) {
          if (_angle(places[stop], places[hub]) < local) return hub;
        }
        hubs.add(stop);
        return stop;
      });
    }
    final visits = <_Visit>[];
    for (final stop in route) {
      final hub = hubOf[stop]!;
      if (visits.isNotEmpty && visits.last.place == hub) {
        visits.last.stops.add(stop);
      } else {
        visits.add(_Visit(hub, [stop]));
      }
    }
    int pair(int a, int b) => min(a, b) * places.length + max(a, b);
    final flown = <int>{};
    final flights = [visits.first];
    var at = 0;
    while (at + 1 < visits.length) {
      int? back;
      for (var next = at + 1; next < visits.length; next++) {
        if (!flown.contains(pair(visits[next - 1].place, visits[next].place))) {
          break;
        }
        if (visits[next].place == visits[at].place) back = next;
      }
      if (back != null) {
        for (var skipped = at + 1; skipped <= back; skipped++) {
          flights.last.detours.addAll(visits[skipped].stops);
        }
        at = back;
        continue;
      }
      flown.add(pair(visits[at].place, visits[at + 1].place));
      flights.add(visits[at + 1]);
      at++;
    }
    return flights;
  }

  double get endMs => introMs + journeyMs;

  _Vector get start => places[legs.isEmpty ? landings.first : legs.first.from];

  int legAt(double ms) {
    var index = 0;
    while (index + 1 < legs.length && ms >= legs[index + 1].startMs) {
      index++;
    }
    return index;
  }

  int pinned(double ms) => pinnedMs.where((at) => at <= ms).length;
}

class _EagerPanRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _GlobeView extends StatefulWidget {
  const _GlobeView({
    required this.world,
    required this.globe,
    required this.photos,
    required this.photo,
    required this.pins,
    required this.active,
  });

  static const center = Offset(195, 348);
  static const radius = 160.0;

  final _World world;
  final rust.Globe globe;
  final List<EnteFile?> photos;
  final RewindPhotoBuilder photo;
  final RewindDecoded? pins;
  final bool active;

  @override
  State<_GlobeView> createState() => _GlobeViewState();
}

class _GlobeViewState extends State<_GlobeView>
    with SingleTickerProviderStateMixin {
  static const _followMs = 320.0;
  static const _approachMs = 90.0;
  static const _handsOffMs = 2600.0;
  static const _steepest = 58.0;
  static const _apart = 0.36;
  static const _callouts = 6;
  static const _nearby = 0.035;
  static const _slots = [-128.0, -98.0, -8.0, 28.0, 62.0, 118.0, 152.0, 188.0];

  late final _reel = RewindPageScope.reelOf(context);
  late final _reelPace = max(1.0, _world.journeyMs / GlobePage._reelJourneyMs);
  late final Ticker _ticker = createTicker(_onTick);
  var _last = Duration.zero;
  var _ms = 0.0;
  late _Vector _view = _approach(0);
  late _Vector _lead = _view;
  var _handsOnUntil = -1.0;
  var _fling = Offset.zero;
  late final List<double> _shown = List.filled(widget.world.places.length, 0);
  var _landed = 0;

  _World get _world => widget.world;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_GlobeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final still = MediaQuery.disableAnimationsOf(context);
    if (still) {
      _ticker.stop();
      if (_ms < _world.endMs) {
        _ms = _world.endMs + 5000;
        _view = _world.home;
        _lead = _view;
        _settle();
      }
      return;
    }
    if (widget.active && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    } else if (!widget.active && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _settle() {
    final wanted = _wanted();
    for (var place = 0; place < _shown.length; place++) {
      _shown[place] = wanted.contains(place) ? 1 : 0;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  _Vector _approach(double ms) {
    final first = _world.start;
    final swing =
        1 - Curves.easeOutCubic.transform((ms / _World.introMs).clamp(0, 1));
    final turn = -1.3 * swing;
    return (
      x: first.x * cos(turn) + first.z * sin(turn),
      y: first.y,
      z: -first.x * sin(turn) + first.z * cos(turn),
    );
  }

  ({_Vector at, double lift, double glide, int leg, bool flying}) _ducky(
    double ms,
  ) {
    final legs = _world.legs;
    if (legs.isEmpty || ms <= legs.first.startMs) {
      return (at: _world.start, lift: 0, glide: 0, leg: -1, flying: false);
    }
    final index = _world.legAt(ms);
    final leg = legs[index];
    final t = ((ms - leg.startMs) / leg.flightMs).clamp(0.0, 1.0);
    final eased = Curves.easeInOutSine.transform(t);
    return (
      at: _between(_world.places[leg.from], _world.places[leg.to], eased),
      lift: sin(pi * eased) * min(1, leg.angle / 0.5),
      glide: sin(pi * eased),
      leg: index,
      flying: t < 1,
    );
  }

  void _onTick(Duration elapsed) {
    final travelling = _ms >= _World.introMs && _ms < _world.endMs;
    final dt =
        (elapsed - _last).inMicroseconds /
        1000 *
        (_reel && travelling ? _reelPace : 1);
    _last = elapsed;
    if (dt <= 0) return;
    _ms += dt;
    final ducky = _ducky(_ms);
    final landed = _landedAt(ducky.leg, flying: ducky.flying);
    if (landed != _landed) {
      if (landed > _landed && !_reel) HapticFeedback.selectionClick();
      _landed = landed;
    }
    if (_ms < _handsOnUntil) {
      if (_fling != Offset.zero) {
        _turn(_fling * (dt / 1000));
        _fling *= exp(-dt / 420);
        if (_fling.distance < 4) _fling = Offset.zero;
      }
      _lead = _view;
    } else {
      final target = _ms < _World.introMs
          ? _approach(_ms)
          : _ms < _world.endMs
          ? ducky.at
          : _sway(_ms - _world.endMs);
      final pull =
          1 - exp(-dt / (_ms < _World.introMs ? _approachMs : _followMs));
      _lead = _towards(_lead, target, pull);
      _view = _towards(_view, _lead, pull);
    }
    final ease = 1 - exp(-dt / 200);
    final wanted = _wanted();
    for (var place = 0; place < _shown.length; place++) {
      _shown[place] +=
          ((wanted.contains(place) ? 1 : 0) - _shown[place]) * ease;
    }
    setState(() {});
  }

  static int _landedAt(int leg, {required bool flying}) =>
      leg < 0 ? 0 : leg + (flying ? 0 : 1);

  static _Vector _towards(_Vector from, _Vector to, double pull) => _unit((
    x: from.x + (to.x - from.x) * pull,
    y: from.y + (to.y - from.y) * pull,
    z: from.z + (to.z - from.z) * pull,
  ));

  _Vector _sway(double ms) {
    final turn = 0.3 * sin(ms / 2600);
    final home = _world.home;
    return (
      x: home.x * cos(turn) + home.z * sin(turn),
      y: home.y,
      z: -home.x * sin(turn) + home.z * cos(turn),
    );
  }

  static _Vector _unit(_Vector vector) {
    final length = sqrt(
      vector.x * vector.x + vector.y * vector.y + vector.z * vector.z,
    );
    return length < 1e-9
        ? (x: 0, y: 0, z: 1)
        : (x: vector.x / length, y: vector.y / length, z: vector.z / length);
  }

  ({double latitude, double longitude}) get _facing => (
    latitude: (asin(_view.y.clamp(-1.0, 1.0)) * 180 / pi).clamp(
      -_steepest,
      _steepest,
    ),
    longitude: atan2(_view.x, _view.z) * 180 / pi,
  );

  void _turn(Offset drag) {
    final facing = _facing;
    _view = _vector(
      (facing.latitude + drag.dy * 180 / (pi * _GlobeView.radius)).clamp(
        -_steepest,
        _steepest,
      ),
      facing.longitude - drag.dx * 180 / (pi * _GlobeView.radius),
    );
  }

  late final Map<int, Offset> _berths = _berth();

  static List<int> docked(
    _World world,
    rust.Globe globe,
    List<EnteFile?> photos,
  ) {
    final home = _Projection.towards(world.home, _steepest);
    final seen =
        [
          for (var place = 0; place < photos.length; place++)
            if (home.project(world.places[place], 1).depth > 0.2) place,
        ]..sort(
          (a, b) =>
              globe.places[b].photoCount.compareTo(globe.places[a].photoCount),
        );
    return _spaced(world, photos, seen, _callouts, _nearby).toList();
  }

  Map<int, Offset> _berth() {
    final home = _Projection.towards(_world.home, _steepest);
    final docking = docked(_world, widget.globe, widget.photos);
    double bearing(int place) {
      final at = home.project(_world.places[place], 1).at;
      return atan2(at.dy, at.dx);
    }

    double apart(double a, double b) => (atan2(sin(a - b), cos(a - b))).abs();
    final free = [for (final slot in _slots) slot * pi / 180];
    final taken = <double>[];
    for (final place in docking) {
      final towards = bearing(place);
      free.sort((a, b) => apart(a, towards).compareTo(apart(b, towards)));
      taken.add(free.removeAt(0));
    }
    docking.sort((a, b) => bearing(a).compareTo(bearing(b)));
    taken.sort();
    var best = 0;
    var bestCost = double.infinity;
    for (var shift = 0; shift < taken.length; shift++) {
      var cost = 0.0;
      for (var i = 0; i < docking.length; i++) {
        cost += apart(taken[(i + shift) % taken.length], bearing(docking[i]));
      }
      if (cost < bestCost) {
        bestCost = cost;
        best = shift;
      }
    }
    return {
      for (var i = 0; i < docking.length; i++)
        docking[i]: _dock(taken[(i + best) % taken.length]),
    };
  }

  static Offset _dock(double slot) {
    final berth =
        _GlobeView.center + Offset.fromDirection(slot, _GlobeView.radius - 2);
    return Offset(berth.dx.clamp(36.0, 354.0), berth.dy);
  }

  static Set<int> _spaced(
    _World world,
    List<EnteFile?> photos,
    Iterable<int> candidates,
    int limit,
    double apart,
  ) {
    final chosen = <int>[];
    for (final place in candidates) {
      if (chosen.length >= limit) break;
      if (photos[place] == null) continue;
      final crowded = chosen.any(
        (other) => _angle(world.places[place], world.places[other]) < apart,
      );
      if (!crowded) chosen.add(place);
    }
    return chosen.toSet();
  }

  Set<int> _wanted() {
    if (_ms >= _world.endMs) return _berths.keys.toSet();
    final pinned = [
      for (final place in _berths.keys)
        if (_world.pinnedMs[place] <= _ms) place,
    ]..sort((a, b) => _world.pinnedMs[a].compareTo(_world.pinnedMs[b]));
    return _spaced(_world, widget.photos, pinned, _callouts, _apart);
  }

  ({int place, EnteFile photo, Offset at, Offset pin, double size, double pop})
  _callout(_Projection projection, int place, EnteFile photo) {
    final point = projection.project(_world.places[place], 1);
    final pin = _GlobeView.center + point.at * _GlobeView.radius;
    final lifted = Offset(pin.dx, max(204.0, pin.dy - 56));
    final berth = _berths[place];
    final docked = berth == null
        ? 0.0
        : Curves.easeInOutCubic.transform(
            ((_ms - _world.endMs) / 900).clamp(0.0, 1.0),
          );
    return (
      place: place,
      photo: photo,
      at: berth == null ? lifted : Offset.lerp(lifted, berth, docked)!,
      pin: pin,
      size: 50 + 10 * docked,
      pop:
          Curves.easeOutCubic.transform(_shown[place].clamp(0.0, 1.0)) *
          ((point.depth - 0.1) / 0.25).clamp(0.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final facing = _facing;
    final projection = _Projection(facing.latitude, facing.longitude);
    final ducky = _ducky(_ms);
    final here = widget
        .globe
        .places[_world.landings[_landedAt(ducky.leg, flying: ducky.flying)]];
    final done = _ms >= _world.endMs;
    final entered = Curves.easeOutCubic.transform((_ms / 900).clamp(0.0, 1.0));
    final callouts = [
      for (var place = 0; place < widget.photos.length; place++)
        if (widget.photos[place] case final photo? when _shown[place] > 0.02)
          _callout(projection, place, photo),
    ];
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: CustomPaint(painter: _StarsPainter(_ms))),
        Positioned.fromRect(
          rect: Rect.fromCircle(
            center: _GlobeView.center,
            radius: _GlobeView.radius + 40,
          ),
          child: Transform.scale(
            scale: 0.72 + 0.28 * entered,
            child: Opacity(
              opacity: (_ms / 220).clamp(0.0, 1.0),
              child: CustomPaint(
                painter: _GlobePainter(
                  world: _world,
                  projection: projection,
                  ms: _ms,
                  pinned: _world.pinned(_ms),
                  ducky: ducky.leg,
                  flown: ducky.leg < 0
                      ? 0
                      : ((_ms - _world.legs[ducky.leg].startMs) /
                                _world.legs[ducky.leg].flightMs)
                            .clamp(0.0, 1.0),
                ),
              ),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: Rect.fromCircle(
            center: _GlobeView.center,
            radius: _GlobeView.radius,
          ),
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              _EagerPanRecognizer:
                  GestureRecognizerFactoryWithHandlers<_EagerPanRecognizer>(
                    _EagerPanRecognizer.new,
                    (recognizer) => recognizer
                      ..onStart = (_) {
                        _fling = Offset.zero;
                        _handsOnUntil = _ms + _handsOffMs;
                      }
                      ..onUpdate = (details) {
                        _handsOnUntil = _ms + _handsOffMs;
                        setState(() => _turn(details.delta));
                      }
                      ..onEnd = (details) {
                        _fling = details.velocity.pixelsPerSecond;
                        _handsOnUntil = _ms + _handsOffMs;
                      },
                  ),
            },
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _LeadersPainter([
                for (final callout in callouts)
                  (callout.at, callout.pin, callout.pop),
              ]),
            ),
          ),
        ),
        for (final callout in callouts) _sticker(callout),
        _duckyAt(projection, ducky, done),
        Positioned(
          left: 0,
          right: 0,
          top: 118,
          child: Center(
            child: Opacity(
              opacity: (_ms / _World.introMs - 0.6).clamp(0.0, 1.0),
              child: _Board(
                done
                    ? "${rewindCounted(widget.globe.cityCount, "CITY", "CITIES")}"
                          "  ·  "
                          "${rewindCounted(widget.globe.countryCount, "COUNTRY", "COUNTRIES")}"
                    : "${here.name.toUpperCase()}"
                          "${here.countryCode.isEmpty ? "" : ", ${here.countryCode}"}",
                tally: done
                    ? null
                    : "${_world.pinned(_ms)}/${widget.globe.places.length}",
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sticker(
    ({
      int place,
      EnteFile photo,
      Offset at,
      Offset pin,
      double size,
      double pop,
    })
    callout,
  ) {
    return Positioned(
      left: callout.at.dx - callout.size / 2,
      top: callout.at.dy - callout.size / 2,
      width: callout.size,
      height: callout.size,
      child: IgnorePointer(
        ignoring: callout.pop < 0.5,
        child: Transform.scale(
          scale: callout.pop,
          child: Transform.rotate(
            angle: (callout.place.isEven ? -1 : 1) * 0.08,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: RewindColors.cream,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: RewindColors.ink, width: 2.5),
                boxShadow: const [
                  BoxShadow(color: RewindColors.ink, offset: Offset(2.5, 3)),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: widget.photo(
                    callout.photo,
                    decoded: widget.pins?[callout.photo],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _duckyAt(
    _Projection projection,
    ({_Vector at, double lift, double glide, int leg, bool flying}) ducky,
    bool done,
  ) {
    final heading = ducky.leg < 0
        ? 0.0
        : (projection
                      .project(_world.places[_world.legs[ducky.leg].to], 1)
                      .at
                      .dx -
                  projection
                      .project(_world.places[_world.legs[ducky.leg].from], 1)
                      .at
                      .dx)
              .sign;
    final point = projection.project(ducky.at, 1.08 + 0.2 * ducky.lift);
    final onGlobe = _GlobeView.center + point.at * _GlobeView.radius;
    final parked =
        _GlobeView.center +
        Offset(
          _GlobeView.radius * 0.82,
          -_GlobeView.radius * 1.02 + 4 * sin(_ms / 520),
        );
    final home = Curves.easeInOut.transform(
      ((_ms - _world.endMs) / 800).clamp(0.0, 1.0),
    );
    final at = Offset.lerp(onGlobe, parked, home)!;
    final hidden = point.depth < -0.15 && point.at.distance < 1 && home < 0.05;
    const size = 54.0;
    return Positioned(
      left: at.dx - size / 2,
      top: at.dy - size / 2 - 10 * (1 - home),
      width: size,
      height: size,
      child: IgnorePointer(
        child: Opacity(
          opacity: hidden ? 0 : (_ms / _World.introMs - 0.4).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 1 + 0.25 * ducky.lift * (1 - home) + 0.3 * home,
            child: Transform.rotate(
              angle: 0.16 * heading * ducky.glide * (1 - home),
              child: Image.file(RewindAssets.file(RewindAssets.heroDucky)),
            ),
          ),
        ),
      ),
    );
  }
}

class _Projection {
  _Projection(double latitude, double longitude)
    : _sinTilt = sin(latitude * pi / 180),
      _cosTilt = cos(latitude * pi / 180),
      _sinSpin = sin(longitude * pi / 180),
      _cosSpin = cos(longitude * pi / 180);

  final double _sinTilt;
  final double _cosTilt;
  final double _sinSpin;
  final double _cosSpin;

  factory _Projection.towards(_Vector view, double steepest) => _Projection(
    (asin(view.y.clamp(-1.0, 1.0)) * 180 / pi).clamp(-steepest, steepest),
    atan2(view.x, view.z) * 180 / pi,
  );

  ({Offset at, double depth}) project(_Vector point, double altitude) {
    final x = point.x * _cosSpin - point.z * _sinSpin;
    final z = point.x * _sinSpin + point.z * _cosSpin;
    final y = point.y * _cosTilt - z * _sinTilt;
    final depth = point.y * _sinTilt + z * _cosTilt;
    return (at: Offset(x * altitude, -y * altitude), depth: depth * altitude);
  }

  bool sameAs(_Projection other) =>
      _sinTilt == other._sinTilt &&
      _cosTilt == other._cosTilt &&
      _sinSpin == other._sinSpin &&
      _cosSpin == other._cosSpin;
}

class _GlobePainter extends CustomPainter {
  _GlobePainter({
    required this.world,
    required this.projection,
    required this.ms,
    required this.pinned,
    required this.ducky,
    required this.flown,
  });

  static const _ocean = Color(0xFF2F6EF2);
  static const _radius = _GlobeView.radius;

  final _World world;
  final _Projection projection;
  final double ms;
  final int pinned;
  final int ducky;
  final double flown;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(size.width / 2, size.height / 2);
    final ink = Paint()..color = RewindColors.ink;
    canvas.drawCircle(const Offset(6, 7), _radius + 2, ink);
    _arcs(canvas, behind: true);
    canvas.drawCircle(Offset.zero, _radius, Paint()..color = _ocean);
    _land(canvas);
    canvas.drawCircle(
      Offset.zero,
      _radius,
      Paint()
        ..shader = ui.Gradient.radial(
          const Offset(-_radius * 0.35, -_radius * 0.4),
          _radius * 1.5,
          const [Color(0x00151515), Color(0x00151515), Color(0x59151515)],
          const [0, 0.55, 1],
        ),
    );
    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: _radius - 14),
      -2.65,
      0.55,
      false,
      Paint()
        ..color = const Color(0x2EFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset.zero,
      _radius,
      Paint()
        ..color = RewindColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    _arcs(canvas, behind: false);
    _pins(canvas);
  }

  void _land(Canvas canvas) {
    final land = world.land;
    final count = land.length ~/ 3;
    final plain = [<double>[], <double>[], <double>[]];
    final been = [<double>[], <double>[], <double>[]];
    for (var dot = 0; dot < count; dot++) {
      final point = projection.project((
        x: land[dot * 3],
        y: land[dot * 3 + 1],
        z: land[dot * 3 + 2],
      ), 1);
      if (point.depth < 0.03) continue;
      final band = point.depth > 0.72
          ? 0
          : point.depth > 0.38
          ? 1
          : 2;
      (world.visited[dot] == 1 ? been : plain)[band]
        ..add(point.at.dx * _radius)
        ..add(point.at.dy * _radius);
    }
    const sizes = [3.1, 2.6, 1.9];
    for (var band = 0; band < 3; band++) {
      final dot = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = sizes[band];
      canvas.drawRawPoints(
        ui.PointMode.points,
        Float32List.fromList(plain[band]),
        dot..color = RewindColors.cream,
      );
      canvas.drawRawPoints(
        ui.PointMode.points,
        Float32List.fromList(been[band]),
        dot
          ..color = RewindColors.hotPink
          ..strokeWidth = sizes[band] + 0.7,
      );
    }
  }

  void _arcs(Canvas canvas, {required bool behind}) {
    if (ducky < 0) return;
    const steps = 22;
    final path = Path();
    for (var index = 0; index <= ducky; index++) {
      final leg = world.legs[index];
      final reach = index < ducky ? 1.0 : Curves.easeInOutSine.transform(flown);
      final lift = 0.2 * min(1, leg.angle / 0.5);
      Offset? previous;
      for (var step = 0; step <= steps; step++) {
        final t = reach * step / steps;
        final point = projection.project(
          _between(world.places[leg.from], world.places[leg.to], t),
          1.012 + lift * sin(pi * t),
        );
        final hidden = point.depth < 0 && point.at.distance < 1;
        final isBehind = point.depth < 0;
        final at = point.at * _radius;
        if (!hidden && isBehind == behind && previous != null) {
          path
            ..moveTo(previous.dx, previous.dy)
            ..lineTo(at.dx, at.dy);
        }
        previous = hidden || isBehind != behind ? null : at;
      }
    }
    Paint stroke(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, stroke(RewindColors.ink, behind ? 4 : 5.2));
    canvas.drawPath(
      path,
      stroke(
        behind ? const Color(0xFFB38E2E) : RewindColors.yellow,
        behind ? 1.8 : 2.6,
      ),
    );
  }

  void _pins(Canvas canvas) {
    final ink = Paint()..color = RewindColors.ink;
    final dot = Paint()..color = RewindColors.yellow;
    for (final (place, pinnedMs) in world.pinnedMs.indexed) {
      if (pinnedMs > ms) continue;
      final point = projection.project(world.places[place], 1);
      if (point.depth < 0.05) continue;
      final at = point.at * _radius;
      final grown = Curves.easeOutCubic.transform(
        ((ms - pinnedMs) / 260).clamp(0.0, 1.0),
      );
      canvas.drawCircle(at, 5.2 * grown, ink);
      canvas.drawCircle(at, 3 * grown, dot);
    }
  }

  @override
  bool shouldRepaint(_GlobePainter oldDelegate) =>
      !oldDelegate.projection.sameAs(projection) ||
      oldDelegate.pinned != pinned ||
      oldDelegate.ducky != ducky ||
      oldDelegate.flown != flown ||
      world.pinnedMs.any((at) => at <= ms && ms - at < 320);
}

class _LeadersPainter extends CustomPainter {
  _LeadersPainter(this.leaders);

  final List<(Offset, Offset, double)> leaders;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (from, to, strength) in leaders) {
      if (strength <= 0.05) continue;
      final reach = Offset.lerp(to, from, strength)!;
      canvas.drawLine(
        to,
        reach,
        Paint()
          ..color = RewindColors.ink
          ..strokeWidth = 5.5
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        to,
        reach,
        Paint()
          ..color = RewindColors.cream
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(to, 5, Paint()..color = RewindColors.ink);
      canvas.drawCircle(to, 3, Paint()..color = RewindColors.cream);
    }
  }

  @override
  bool shouldRepaint(_LeadersPainter oldDelegate) => true;
}

class _StarsPainter extends CustomPainter {
  _StarsPainter(this.ms);

  final double ms;

  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(26);
    final star = Paint()..color = RewindColors.cream;
    for (var i = 0; i < 46; i++) {
      final at = Offset(
        random.nextDouble() * 390,
        40 + random.nextDouble() * 520,
      );
      final twinkle = 0.7 + 0.3 * sin(ms / 900 + i * 1.7);
      canvas.drawCircle(at, (0.8 + random.nextDouble() * 1.1) * twinkle, star);
    }
  }

  @override
  bool shouldRepaint(_StarsPainter oldDelegate) => oldDelegate.ms != ms;
}

class _Board extends StatelessWidget {
  const _Board(this.text, {this.tally});

  final String text;
  final String? tally;

  @override
  Widget build(BuildContext context) {
    final tally = this.tally;
    return Container(
      constraints: const BoxConstraints(maxWidth: 330),
      padding: const EdgeInsets.fromLTRB(14, 7, 14, 6),
      decoration: BoxDecoration(
        color: RewindColors.hotPink,
        border: Border.all(color: RewindColors.ink, width: 3),
        borderRadius: BorderRadius.circular(7),
        boxShadow: const [
          BoxShadow(color: RewindColors.ink, offset: Offset(3, 4)),
        ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tally != null) ...[
                Text(
                  tally,
                  style: RewindTextStyles.numeral(15, color: RewindColors.ink),
                ),
                const SizedBox(width: 9),
              ],
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                switchInCurve: const Interval(0.5, 1, curve: Curves.easeOut),
                switchOutCurve: const Interval(0.5, 1, curve: Curves.easeIn),
                child: Text(
                  text,
                  key: ValueKey(text),
                  style: RewindTextStyles.display(17, height: 1.1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
