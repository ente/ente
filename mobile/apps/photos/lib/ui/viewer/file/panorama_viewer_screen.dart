import "dart:async";
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:logging/logging.dart";
import "package:panorama/panorama.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/src/rust/api/motion_photo_api.dart";
import "package:photos/ui/viewer/file/panorama_view_data.dart";

final _logger = Logger("PanoramaViewerScreen");

/// Extracts XMP attributes from the file at [filePath].
typedef XmpExtractor = Future<Map<String, String>> Function(String filePath);

class PanoramaViewerScreen extends StatefulWidget {
  const PanoramaViewerScreen({
    super.key,
    required this.file,
    required this.thumbnail,
    this.xmpExtractor,
  });

  final File file;
  final Uint8List? thumbnail;

  /// Overridable for tests. Defaults to the Rust XMP extractor.
  final XmpExtractor? xmpExtractor;

  @override
  State<PanoramaViewerScreen> createState() => _PanoramaViewerScreenState();
}

class _PanoramaViewerScreenState extends State<PanoramaViewerScreen> {
  PanoramaViewData? viewData;
  bool isReady = false;
  SensorControl control = SensorControl.none;
  Timer? timer;
  bool isVisible = true;

  @override
  void initState() {
    initTimer();
    init();
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: isVisible ? AppBar() : null,
      // The Panorama widget must only be created once the view parameters are
      // final: changing its croppedArea afterwards makes it regenerate the
      // sphere mesh, which drops an already-loaded texture and leaves the
      // panorama blank (https://github.com/ente-io/ente/issues/11435).
      body: isReady ? _buildPanorama() : _buildPlaceholder(),
    );
  }

  Widget _buildPlaceholder() {
    if (widget.thumbnail == null) {
      return const SizedBox.shrink();
    }
    return Center(child: Image.memory(widget.thumbnail!));
  }

  Widget _buildPanorama() {
    return Stack(
      children: [
        Panorama(
          onTap: (_, _, _) {
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
          longitude: viewData?.initialLongitude ?? 0.0,
          croppedArea:
              viewData?.croppedArea ?? const Rect.fromLTWH(0.0, 0.0, 1.0, 1.0),
          croppedFullWidth: viewData?.fullWidth ?? 1.0,
          croppedFullHeight: viewData?.fullHeight ?? 1.0,
          sensorControl: control,
          background: widget.thumbnail != null
              ? Image.memory(widget.thumbnail!)
              : null,
          child: Image.file(widget.file),
        ),
        Visibility(
          visible: isVisible,
          child: Align(
            alignment: Alignment.bottomRight,
            child: Tooltip(
              message: AppLocalizations.of(context).panorama,
              child: Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 32, right: 20),
                child: IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF252525),
                    fixedSize: const Size(44, 44),
                  ),
                  icon: Icon(
                    control == SensorControl.none
                        ? Icons.explore_outlined
                        : Icons.explore_off_outlined,
                    color: Colors.white,
                    size: 26,
                  ),
                  onPressed: () async {
                    if (control != SensorControl.none) {
                      control = SensorControl.none;
                    } else {
                      control = SensorControl.orientation;
                    }

                    setState(() {});
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
