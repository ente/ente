import "dart:async";
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:logging/logging.dart";
import "package:panorama/panorama.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/src/rust/api/motion_photo_api.dart";

final _logger = Logger("PanoramaViewerScreen");

class PanoramaViewerScreen extends StatefulWidget {
  const PanoramaViewerScreen({
    super.key,
    required this.file,
    required this.thumbnail,
  });

  final File file;
  final Uint8List? thumbnail;

  @override
  State<PanoramaViewerScreen> createState() => _PanoramaViewerScreenState();
}

class _PanoramaViewerScreenState extends State<PanoramaViewerScreen> {
  double width = 1.0;
  double height = 1.0;
  Rect croppedRect = const Rect.fromLTWH(0.0, 0.0, 1.0, 1.0);
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
    final Map<String, String> data;
    try {
      data = await extractXmp(filePath: widget.file.path);
    } catch (e, s) {
      _logger.warning("Failed to extract panorama XMP", e, s);
      return;
    }
    if (!mounted) {
      return;
    }
    double? cWidth = double.tryParse(
      data["GPano:CroppedAreaImageWidthPixels"] ?? "",
    );
    double? cHeight = double.tryParse(
      data["GPano:CroppedAreaImageHeightPixels"] ?? "",
    );
    double? fWidth = double.tryParse(data["GPano:FullPanoWidthPixels"] ?? "");
    double? fHeight = double.tryParse(data["GPano:FullPanoHeightPixels"] ?? "");
    double? cLeft = double.tryParse(data["GPano:CroppedAreaLeftPixels"] ?? "");
    double? cTop = double.tryParse(data["GPano:CroppedAreaTopPixels"] ?? "");

    // handle missing `fullPanoHeight` (e.g. Samsung camera app panorama mode)
    if (fHeight == null && fWidth != null && cHeight != null) {
      fHeight = (fWidth / 2).round().toDouble();
      cTop = ((fHeight - cHeight) / 2).round().toDouble();
    }

    // handle inconsistent sizing (e.g. rotated image taken with OnePlus EB2103)
    if (cHeight != null && fWidth != null && fHeight != null) {
      final croppedOrientation = cWidth! > cHeight
          ? Orientation.landscape
          : Orientation.portrait;
      final fullOrientation = fWidth > fHeight
          ? Orientation.landscape
          : Orientation.portrait;
      var inconsistent = false;
      if (croppedOrientation != fullOrientation) {
        // inconsistent orientation
        inconsistent = true;
        final tmp = cHeight;
        cHeight = cWidth;
        cWidth = tmp;
      }

      if (cWidth > fWidth) {
        // inconsistent full/cropped width
        inconsistent = true;
        final tmp = fWidth;
        fWidth = cWidth;
        cWidth = tmp;
      }

      if (cHeight > fHeight) {
        // inconsistent full/cropped height
        inconsistent = true;
        final tmp = cHeight;
        cHeight = fHeight;
        fHeight = tmp;
      }

      if (inconsistent) {
        cLeft = ((fWidth - cWidth) ~/ 2).toDouble();
        cTop = ((fHeight - cHeight) ~/ 2).toDouble();
      }
    }

    Rect? croppedAreaRect;
    if (cLeft != null && cTop != null && cWidth != null && cHeight != null) {
      croppedAreaRect = Rect.fromLTWH(
        cLeft.toDouble(),
        cTop.toDouble(),
        cWidth.toDouble(),
        cHeight.toDouble(),
      );
    }

    if (croppedAreaRect == null || fWidth == null || fHeight == null) return;
    width = fWidth.toDouble();
    height = fHeight.toDouble();
    croppedRect = croppedAreaRect;

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: isVisible ? AppBar() : null,
      body: Stack(
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
            croppedArea: croppedRect,
            croppedFullWidth: width,
            croppedFullHeight: height,
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
      ),
    );
  }
}
