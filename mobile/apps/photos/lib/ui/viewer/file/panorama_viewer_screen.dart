import "dart:async";
import "dart:io";
import "dart:ui" as ui;

import "package:ente_panorama_viewer/ente_panorama_viewer.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:hugeicons/hugeicons.dart";
import "package:logging/logging.dart";
import "package:photos/src/rust/api/motion_photo_api.dart";
import "package:photos/ui/viewer/file/panorama_view_data.dart";

final _logger = Logger("PanoramaViewerScreen");

typedef XmpExtractor = Future<Map<String, String>> Function(String filePath);
typedef MotionAvailabilityChecker = Future<bool> Function();

class PanoramaViewerScreen extends StatefulWidget {
  const PanoramaViewerScreen({
    super.key,
    required this.file,
    required this.thumbnail,
    this.xmpExtractor,
    this.motionAvailabilityChecker,
  });

  final File file;
  final Uint8List? thumbnail;

  final XmpExtractor? xmpExtractor;
  final MotionAvailabilityChecker? motionAvailabilityChecker;

  @override
  State<PanoramaViewerScreen> createState() => _PanoramaViewerScreenState();
}

class _PanoramaViewerScreenState extends State<PanoramaViewerScreen> {
  PanoramaViewData? viewData;
  bool isReady = false;
  bool motionAvailable = false;
  bool motionEnabled = false;
  Timer? timer;
  bool isVisible = true;

  @override
  void initState() {
    super.initState();
    initTimer();
    init();
    initMotion();
  }

  @override
  void dispose() {
    timer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void initTimer() {
    timer = Timer(const Duration(seconds: 5), () {
      if (!mounted) {
        return;
      }
      setState(() {
        isVisible = false;
      });
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> init() async {
    Map<String, String>? data;
    try {
      data = await (widget.xmpExtractor ?? _extractXmp)(widget.file.path);
    } catch (e, s) {
      _logger.warning("Failed to extract panorama XMP", e, s);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      viewData = data == null ? null : PanoramaViewData.fromXmp(data);
      isReady = true;
    });
  }

  static Future<Map<String, String>> _extractXmp(String filePath) =>
      extractXmp(filePath: filePath);

  Future<void> initMotion() async {
    bool available;
    try {
      available =
          await (widget.motionAvailabilityChecker ??
              isPanoramaMotionAvailable)();
    } catch (_) {
      available = false;
    }
    if (!mounted) return;
    setState(() {
      motionAvailable = available;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: isVisible
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              foregroundColor: Colors.white,
              systemOverlayStyle: SystemUiOverlayStyle.light,
              flexibleSpace: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.72),
                      Colors.black.withValues(alpha: 0.6),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.2, 1],
                  ),
                ),
              ),
            )
          : null,
      // Keep the thumbnail visible until the final crop is known so the first
      // rendered frame does not jump from a full sphere to a partial panorama.
      body: isReady ? _buildPanorama() : _buildPlaceholder(),
    );
  }

  Widget _buildPlaceholder() {
    if (widget.thumbnail == null) {
      return const SizedBox.shrink();
    }
    return _BlurredThumbnail(widget.thumbnail!);
  }

  Widget _buildPanorama() {
    final data = viewData;
    final geometry = data == null
        ? const PanoramaGeometry.fullSphere()
        : PanoramaGeometry(
            fullSize: Size(data.fullWidth, data.fullHeight),
            croppedArea: data.croppedArea,
          );
    return Stack(
      children: [
        EntePanoramaViewer(
          image: FileImage(widget.file),
          geometry: geometry,
          initialView: PanoramaView(
            longitude: data?.initialLongitude ?? 0,
            latitude: data?.initialLatitude ?? 0,
          ),
          motionEnabled: motionEnabled,
          placeholder: widget.thumbnail == null
              ? null
              : _BlurredThumbnail(widget.thumbnail!),
          onError: (error, stackTrace) {
            _logger.warning("Failed to render panorama", error, stackTrace);
          },
          onTap: () {
            setState(() {
              if (isVisible) {
                timer?.cancel();
                SystemChrome.setEnabledSystemUIMode(
                  SystemUiMode.immersiveSticky,
                );
              } else {
                initTimer();
              }
              isVisible = !isVisible;
            });
          },
        ),
        if (motionAvailable)
          Visibility(
            visible: isVisible,
            child: Align(
              alignment: Alignment.bottomRight,
              child: Tooltip(
                message: context.strings.panorama,
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: 12,
                    bottom: 32,
                    right: 20,
                  ),
                  child: IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF252525),
                      fixedSize: const Size(44, 44),
                    ),
                    icon: HugeIcon(
                      icon: !motionEnabled
                          ? HugeIcons.strokeRoundedNavigation05
                          : HugeIcons.strokeRoundedNavigationOff,
                      color: Colors.white,
                      size: 24,
                    ),
                    onPressed: () {
                      setState(() {
                        motionEnabled = !motionEnabled;
                      });
                    },
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BlurredThumbnail extends StatelessWidget {
  const _BlurredThumbnail(this.bytes);

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: 32,
          sigmaY: 32,
          tileMode: TileMode.mirror,
        ),
        child: Transform.scale(
          scale: 1.1,
          child: Image.memory(
            bytes,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
