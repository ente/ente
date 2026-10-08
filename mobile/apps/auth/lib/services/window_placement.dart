import 'dart:ui';

Rect readRect(Map<dynamic, dynamic> json) {
  final values = [
    'x',
    'y',
    'width',
    'height',
  ].map((key) => (json[key] as num).toDouble()).toList();
  if (values.any((v) => !v.isFinite) || values[2] <= 0 || values[3] <= 0) {
    throw const FormatException('Invalid window rectangle');
  }
  return Rect.fromLTWH(values[0], values[1], values[2], values[3]);
}

Map<String, double> rectJson(Rect rect) => {
  'x': rect.left,
  'y': rect.top,
  'width': rect.width,
  'height': rect.height,
};

class Monitor {
  const Monitor(this.id, this.workArea, this.scale, {this.primary = false});
  final String id;
  final Rect workArea;
  final double scale;
  final bool primary;
  factory Monitor.fromJson(Map<dynamic, dynamic> json) => Monitor(
    json['id'] as String,
    readRect(json['workArea'] as Map),
    (json['dpi'] as num) / 96,
    primary: json['primary'] as bool,
  );
}

class Placement {
  const Placement(this.monitorId, this.logicalBounds, this.maximized);
  final String monitorId;
  final Rect logicalBounds;
  final bool maximized;
  factory Placement.fromJson(Map<String, dynamic> json) => Placement(
    json['monitorId'] as String,
    readRect(json['logicalBounds'] as Map),
    json['maximized'] as bool,
  );
  Map<String, dynamic> toJson() => {
    'monitorId': monitorId,
    'logicalBounds': rectJson(logicalBounds),
    'maximized': maximized,
  };
}

Rect fitToWorkArea(Rect bounds, Rect workArea) {
  final width = bounds.width.clamp(1.0, workArea.width);
  final height = bounds.height.clamp(1.0, workArea.height);
  return Rect.fromLTWH(
    bounds.left.clamp(workArea.left, workArea.right - width),
    bounds.top.clamp(workArea.top, workArea.bottom - height),
    width,
    height,
  );
}

Rect restoreBounds(
  Placement? placement,
  List<Monitor> monitors,
  Size fallbackSize,
) {
  if (monitors.isEmpty) throw StateError('No monitors reported');
  final monitor = monitors.firstWhere(
    (m) => m.id == placement?.monitorId,
    orElse: () =>
        monitors.firstWhere((m) => m.primary, orElse: () => monitors.first),
  );
  final logical =
      placement?.logicalBounds ??
      Rect.fromLTWH(70, 70, fallbackSize.width, fallbackSize.height);
  return fitToWorkArea(
    Rect.fromLTWH(
      monitor.workArea.left + logical.left * monitor.scale,
      monitor.workArea.top + logical.top * monitor.scale,
      logical.width * monitor.scale,
      logical.height * monitor.scale,
    ),
    monitor.workArea,
  );
}

Placement captureBounds(Rect bounds, Monitor monitor, bool maximized) =>
    Placement(
      monitor.id,
      Rect.fromLTWH(
        (bounds.left - monitor.workArea.left) / monitor.scale,
        (bounds.top - monitor.workArea.top) / monitor.scale,
        bounds.width / monitor.scale,
        bounds.height / monitor.scale,
      ),
      maximized,
    );
