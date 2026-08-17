import "dart:async";
import "dart:isolate";
import "dart:math";

import "package:computer/computer.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:ente_strings/ente_strings.dart";
import "package:ente_ui/components/loading_widget.dart";
import "package:flutter/foundation.dart";
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import "package:latlong2/latlong.dart";
import "package:logging/logging.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/models/location/location.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/map/image_marker.dart";
import "package:photos/ui/map/map_isolate.dart";
import "package:photos/ui/map/map_pull_up_gallery.dart";
import "package:photos/ui/map/map_view.dart";
import "package:photos/ui/notification/toast.dart";

class MapScreen extends StatefulWidget {
  final Future<List<EnteFile>> Function() filesFutureFn;
  final LatLng? center;
  final double initialZoom;

  const MapScreen({
    super.key,
    required this.filesFutureFn,
    this.center,
    this.initialZoom = 4.5,
  });

  @override
  State<StatefulWidget> createState() {
    return _MapScreenState();
  }
}

class _MapScreenState extends State<MapScreen> {
  List<ImageMarker> imageMarkers = [];
  List<EnteFile> allImages = [];
  StreamController<List<EnteFile>> visibleImages =
      StreamController<List<EnteFile>>.broadcast();
  MapController mapController = MapController();
  bool isLoading = true;
  bool hasLocationData = true;
  double maxZoom = 18.0;
  double minZoom = 2.8;
  LatLng? center;
  final Logger _logger = Logger("_MapScreenState");
  ReceivePort? _mapWorkerReceivePort;
  StreamSubscription? _mapWorkerSubscription;
  SendPort? _mapWorkerSendPort;
  Isolate? _mapWorkerIsolate;
  static const bottomSheetDraggableAreaHeight = 32.0;
  List<int>? _previousVisibleIndexes;
  int _viewportRequestID = 0;
  final _viewportDebouncer = Debouncer(
    const Duration(milliseconds: 300),
    executionInterval: const Duration(milliseconds: 750),
  );
  static const _markerViewportPaddingPixels = 256.0;

  @override
  void initState() {
    super.initState();
    initialize();
  }

  @override
  void dispose() {
    _viewportDebouncer.cancelDebounceTimer();
    unawaited(_mapWorkerSubscription?.cancel());
    _mapWorkerReceivePort?.close();
    _mapWorkerIsolate?.kill();
    unawaited(visibleImages.close());
    super.dispose();
  }

  Future<void> initialize() async {
    try {
      center = widget.center;
      allImages = await widget.filesFutureFn();
      await processFiles(allImages);
    } catch (e, s) {
      _logger.severe("Error initializing map screen", e, s);
    }
  }

  Future<void> processFiles(List<EnteFile> files) async {
    final result = await Computer.shared().compute(
      _findRecentImageAndMapPoints,
      param: {"files": files, "center": widget.center},
    );

    final int? initialCenterImageIndex = result.$1;
    final List<MapPoint> mapPoints = result.$2;

    if (mapPoints.isEmpty) {
      if (!mounted) return;
      showShortToast(context, context.strings.noImagesWithLocation);
      if (!visibleImages.isClosed) {
        visibleImages.sink.add([]);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        hasLocationData = false;
        imageMarkers = [];
        isLoading = false;
      });
      return;
    }

    center =
        widget.center ??
        LatLng(
          allImages[initialCenterImageIndex!].location!.latitude!,
          allImages[initialCenterImageIndex].location!.longitude!,
        );

    if (kDebugMode) {
      debugPrint(
        "Info for map: center $center, initialZoom ${widget.initialZoom}",
      );
    }

    await _startMapWorker(mapPoints);
    if (!mounted) return;
    setState(() {
      hasLocationData = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _sendViewportRequest(mapController.camera, ++_viewportRequestID);
    });
  }

  Future<void> _startMapWorker(List<MapPoint> mapPoints) async {
    final receivePort = ReceivePort();
    final sendPortCompleter = Completer<SendPort>();
    final subscription = receivePort.listen((message) {
      if (message is SendPort) {
        if (!sendPortCompleter.isCompleted) {
          sendPortCompleter.complete(message);
        }
      } else if (message is MapViewportResult) {
        _applyViewportResult(message);
      }
    });
    final isolate = await Isolate.spawn(
      mapWorker,
      MapWorkerInit(points: mapPoints, sendPort: receivePort.sendPort),
    );
    final sendPort = await sendPortCompleter.future;

    if (!mounted) {
      await subscription.cancel();
      receivePort.close();
      isolate.kill();
      return;
    }

    _mapWorkerReceivePort = receivePort;
    _mapWorkerSubscription = subscription;
    _mapWorkerSendPort = sendPort;
    _mapWorkerIsolate = isolate;
  }

  void _updateViewport(MapCamera camera) {
    final requestID = ++_viewportRequestID;
    _viewportDebouncer.run(() async {
      _sendViewportRequest(camera, requestID);
    });
  }

  void _sendViewportRequest(MapCamera camera, int requestID) {
    final sendPort = _mapWorkerSendPort;
    if (sendPort == null) return;
    final pixelBounds = camera.pixelBounds;
    sendPort.send(
      MapViewportRequest(
        id: requestID,
        bounds: camera.visibleBounds,
        zoom: camera.zoom,
        markerMinX: pixelBounds.left - _markerViewportPaddingPixels,
        markerMinY: pixelBounds.top - _markerViewportPaddingPixels,
        markerMaxX: pixelBounds.right + _markerViewportPaddingPixels,
        markerMaxY: pixelBounds.bottom + _markerViewportPaddingPixels,
      ),
    );
  }

  void _applyViewportResult(MapViewportResult result) {
    if (!mounted || result.id != _viewportRequestID) return;

    final visibleIndexes = result.visibleImageIndexes;
    if (!_sameIndexes(visibleIndexes, _previousVisibleIndexes)) {
      _previousVisibleIndexes = visibleIndexes;
      if (!visibleImages.isClosed) {
        visibleImages.add(
          visibleIndexes
              .map((index) => allImages[index])
              .toList(growable: false),
        );
      }
    }

    setState(() {
      imageMarkers = result.markerGroups
          .map(
            (group) => ImageMarker(
              imageFile: allImages[group.imageIndex],
              latitude: group.latitude,
              longitude: group.longitude,
              imageCount: group.imageCount,
              clusterBounds: group.imageCount > 1 ? group.bounds : null,
            ),
          )
          .toList(growable: false);
      isLoading = false;
    });
  }

  bool _sameIndexes(List<int> current, List<int>? previous) {
    if (previous == null || current.length != previous.length) return false;
    for (var i = 0; i < current.length; i++) {
      if (current[i] != previous[i]) return false;
    }
    return true;
  }

  static (int?, List<MapPoint>) _findRecentImageAndMapPoints(
    Map<String, dynamic> args,
  ) {
    final Logger logger = Logger("_MapScreenState");
    final files = args["files"] as List<EnteFile>;
    final center = args["center"] as LatLng?;
    final List<MapPoint> mapPoints = [];
    final recentImageIndexes = <int>[];

    for (var index = 0; index < files.length; index++) {
      final file = files[index];
      if (file.hasLocation) {
        if (!Location.isValidRange(
          latitude: file.location!.latitude!,
          longitude: file.location!.longitude!,
        )) {
          logger.warning(
            'Skipping file with invalid location ${file.toString()}',
          );
          continue;
        }

        if (center == null) {
          _insertRecentImageIndex(files, recentImageIndexes, index);
        }

        mapPoints.add(
          MapPoint(
            imageIndex: index,
            latitude: file.location!.latitude!,
            longitude: file.location!.longitude!,
          ),
        );
      }
    }

    return (
      center == null
          ? _findInitialCenterImageIndex(files, recentImageIndexes)
          : null,
      mapPoints,
    );
  }

  static void _insertRecentImageIndex(
    List<EnteFile> files,
    List<int> recentImageIndexes,
    int imageIndex,
  ) {
    const sampleSize = 10;
    final creationTime = files[imageIndex].creationTime ?? 0;
    final insertAt = recentImageIndexes.indexWhere(
      (index) => (files[index].creationTime ?? 0) < creationTime,
    );
    if (insertAt < 0) {
      if (recentImageIndexes.length < sampleSize) {
        recentImageIndexes.add(imageIndex);
      }
    } else {
      recentImageIndexes.insert(insertAt, imageIndex);
      if (recentImageIndexes.length > sampleSize) {
        recentImageIndexes.removeLast();
      }
    }
  }

  static int? _findInitialCenterImageIndex(
    List<EnteFile> files,
    List<int> recentImageIndexes,
  ) {
    if (recentImageIndexes.isEmpty) return null;

    const clusterRadiusInKm = 50.0;
    var clusterSeed = recentImageIndexes.first;
    var largestClusterSize = 0;

    for (final candidate in recentImageIndexes) {
      var clusterSize = 0;
      for (final other in recentImageIndexes) {
        if (_distanceInKm(files[candidate], files[other]) <=
            clusterRadiusInKm) {
          clusterSize++;
        }
      }
      if (clusterSize > largestClusterSize) {
        clusterSeed = candidate;
        largestClusterSize = clusterSize;
      }
    }

    final cluster = recentImageIndexes
        .where(
          (index) =>
              _distanceInKm(files[clusterSeed], files[index]) <=
              clusterRadiusInKm,
        )
        .toList(growable: false);
    var medoid = cluster.first;
    var shortestTotalDistance = double.infinity;
    for (final candidate in cluster) {
      var totalDistance = 0.0;
      for (final other in cluster) {
        totalDistance += _distanceInKm(files[candidate], files[other]);
      }
      if (totalDistance < shortestTotalDistance) {
        medoid = candidate;
        shortestTotalDistance = totalDistance;
      }
    }
    return medoid;
  }

  static double _distanceInKm(EnteFile first, EnteFile second) {
    const earthRadiusInKm = 6371.0;
    final firstLatitude = first.location!.latitude! * pi / 180;
    final secondLatitude = second.location!.latitude! * pi / 180;
    final latitudeDelta = secondLatitude - firstLatitude;
    final longitudeDelta =
        (second.location!.longitude! - first.location!.longitude!) * pi / 180;
    final haversine =
        sin(latitudeDelta / 2) * sin(latitudeDelta / 2) +
        cos(firstLatitude) *
            cos(secondLatitude) *
            sin(longitudeDelta / 2) *
            sin(longitudeDelta / 2);
    final normalizedHaversine = haversine.clamp(0.0, 1.0);
    return earthRadiusInKm *
        2 *
        atan2(sqrt(normalizedHaversine), sqrt(1 - normalizedHaversine));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final bottomUnsafeArea = MediaQuery.of(context).padding.bottom;
    final initialCenter = center;
    return Container(
      color: colorScheme.backgroundColour,
      child: Theme(
        data: Theme.of(context).copyWith(
          bottomSheetTheme: const BottomSheetThemeData(
            backgroundColor: Colors.transparent,
          ),
        ),
        child: Scaffold(
          body: Stack(
            children: [
              LayoutBuilder(
                builder: (context, constrains) {
                  return SizedBox(
                    height:
                        constrains.maxHeight * 0.75 +
                        bottomSheetDraggableAreaHeight -
                        bottomUnsafeArea,
                    child: initialCenter == null
                        ? const SizedBox.shrink()
                        : MapView(
                            controller: mapController,
                            imageMarkers: imageMarkers,
                            updateViewport: _updateViewport,
                            center: initialCenter,
                            initialZoom: widget.initialZoom,
                            minZoom: minZoom,
                            maxZoom: maxZoom,
                            bottomSheetDraggableAreaHeight:
                                bottomSheetDraggableAreaHeight,
                          ),
                  );
                },
              ),
              isLoading
                  ? Positioned.fill(
                      child: ColoredBox(
                        color: colorScheme.backgroundColour,
                        child: EnteLoadingWidget(
                          size: 28,
                          color: colorScheme.primary700,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ],
          ),
          bottomSheet: MapPullUpGallery(
            visibleImages,
            bottomSheetDraggableAreaHeight,
            bottomUnsafeArea,
            hasLocationData: hasLocationData,
          ),
        ),
      ),
    );
  }
}
