import "dart:async";
import "dart:isolate";

import "package:collection/collection.dart";
import "package:computer/computer.dart";
import "package:flutter/foundation.dart";
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import "package:latlong2/latlong.dart";
import "package:logging/logging.dart";
import "package:photos/generated/l10n.dart";
import 'package:photos/models/file/file.dart';
import "package:photos/models/location/location.dart";
import "package:photos/theme/ente_theme.dart";
import "package:photos/ui/common/loading_widget.dart";
import "package:photos/ui/map/image_marker.dart";
import "package:photos/ui/map/map_isolate.dart";
import "package:photos/ui/map/map_pull_up_gallery.dart";
import "package:photos/ui/map/map_view.dart";
import "package:photos/ui/notification/toast.dart";

class MapScreen extends StatefulWidget {
  // Add a function parameter where the function returns a Future<List<File>>

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
  int debounceDuration = 500;
  late LatLng center;
  final Logger _logger = Logger("_MapScreenState");
  StreamSubscription? _mapMoveSubscription;
  Isolate? isolate;
  static const bottomSheetDraggableAreaHeight = 32.0;
  List<EnteFile>? prevMessage;

  @override
  void initState() {
    super.initState();
    initialize();
  }

  @override
  void dispose() {
    super.dispose();
    visibleImages.close();
    _mapMoveSubscription?.cancel();
  }

  Future<void> initialize() async {
    try {
      center = widget.center ?? const LatLng(46.7286, 4.8614);
      allImages = await widget.filesFutureFn();
      unawaited(processFiles(allImages));
    } catch (e, s) {
      _logger.severe("Error initializing map screen", e, s);
    }
  }

  Future<void> processFiles(List<EnteFile> files) async {
    final result = await Computer.shared().compute(
      _findRecentFileAndGenerateTempMarkers,
      param: {"files": files, "center": widget.center},
    );

    final EnteFile? mostRecentFile = result.$1;
    final List<ImageMarker> tempMarkers = result.$2;

    if (tempMarkers.isEmpty) {
      if (!mounted) return;
      showShortToast(
        context,
        AppLocalizations.of(context).noImagesWithLocation,
      );
      if (!visibleImages.isClosed) {
        visibleImages.sink.add([]);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        hasLocationData = false;
        imageMarkers = tempMarkers;
        isLoading = false;
      });
      return;
    }

    center =
        widget.center ??
        LatLng(
          mostRecentFile!.location!.latitude!,
          mostRecentFile.location!.longitude!,
        );

    if (kDebugMode) {
      debugPrint(
        "Info for map: center $center, initialZoom ${widget.initialZoom}",
      );
    }

    setState(() {
      hasLocationData = true;
      imageMarkers = tempMarkers;
    });

    mapController.move(center, widget.initialZoom);

    Timer(Duration(milliseconds: debounceDuration), () {
      if (!mounted) {
        return;
      }
      calculateVisibleMarkers(mapController.camera.visibleBounds);
      setState(() {
        isLoading = false;
      });
    });
  }

  void calculateVisibleMarkers(LatLngBounds bounds) async {
    final ReceivePort receivePort = ReceivePort();
    isolate = await Isolate.spawn<MapIsolate>(
      _calculateMarkersIsolate,
      MapIsolate(
        bounds: bounds,
        imageMarkers: imageMarkers,
        sendPort: receivePort.sendPort,
      ),
    );

    _mapMoveSubscription = receivePort.listen((dynamic message) async {
      if (message is List<EnteFile>) {
        if (!message.equals(prevMessage ?? [])) {
          if (visibleImages.isClosed) {
            return;
          }
          visibleImages.sink.add(message);
        }

        prevMessage = message;
      } else {
        await _mapMoveSubscription?.cancel();
        isolate?.kill();
      }
    });
  }

  static (EnteFile?, List<ImageMarker>) _findRecentFileAndGenerateTempMarkers(
    Map<String, dynamic> args,
  ) {
    final Logger logger = Logger("_MapScreenState");
    final files = args["files"] as List<EnteFile>;
    final center = args["center"] as LatLng?;
    final List<ImageMarker> tempMarkers = [];
    EnteFile? mostRecentFile;

    for (var file in files) {
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
          if (mostRecentFile == null) {
            mostRecentFile = file;
          } else {
            if ((mostRecentFile.creationTime ?? 0) < (file.creationTime ?? 0)) {
              mostRecentFile = file;
            }
          }
        }

        tempMarkers.add(
          ImageMarker(
            latitude: file.location!.latitude!,
            longitude: file.location!.longitude!,
            imageFile: file,
          ),
        );
      }
    }

    return (mostRecentFile, tempMarkers);
  }

  @pragma('vm:entry-point')
  static void _calculateMarkersIsolate(MapIsolate message) async {
    final bounds = message.bounds;
    final imageMarkers = message.imageMarkers;
    final SendPort sendPort = message.sendPort;
    try {
      final List<EnteFile> visibleFiles = [];
      for (var imageMarker in imageMarkers) {
        final point = LatLng(imageMarker.latitude, imageMarker.longitude);
        if (bounds.contains(point)) {
          visibleFiles.add(imageMarker.imageFile);
        }
      }
      sendPort.send(visibleFiles);
    } catch (e) {
      sendPort.send(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = getEnteColorScheme(context);
    final bottomUnsafeArea = MediaQuery.of(context).padding.bottom;
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
                    child: MapView(
                      key: ValueKey(
                        'image-marker-count-${imageMarkers.length}',
                      ),
                      controller: mapController,
                      imageMarkers: imageMarkers,
                      updateVisibleImages: calculateVisibleMarkers,
                      center: center,
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
                  ? EnteLoadingWidget(
                      size: 28,
                      color: getEnteColorScheme(context).primary700,
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
