import "dart:async";
import "dart:io";
import "dart:typed_data";

import "package:ffmpeg_kit_flutter/ffmpeg_kit.dart";
import "package:ffmpeg_kit_flutter/return_code.dart";
import "package:flutter/cupertino.dart";
import "package:image/image.dart" as img;
import "package:logging/logging.dart";
import "package:path_provider/path_provider.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/ui/notification/toast.dart";
import "package:photos/utils/dialog_util.dart";
import "package:photos/utils/file_util.dart";

final _logger = Logger("VideoMemoryService");

Future<void> createSlideshow(BuildContext context, List<EnteFile> files) async {
  final dialog = createProgressDialog(context, "Creating video...");

  try {
    await dialog.show();

    final imageData = await _prepareImageFiles(files);

    if (imageData.paths.isEmpty) {
      await dialog.hide();
    }

    if (!context.mounted) return;
    final command = _buildFFmpegCommand(
      context,
      imageData.paths,
      imageData.heights,
      imageData.widths,
    );

    if (!context.mounted) return;
    await _executeFFmpegProcess(
      context: context,
      command: command,
      onComplete: () {
        dialog.hide();
      },
    );
  } catch (e) {
    _logger.severe("Error creating slideshow: $e");
    await dialog.hide();
  }
}

Future<ImageProcessingResult> _prepareImageFiles(List<EnteFile> files) async {
  final List<String> paths = [];
  final List<double> heights = [];
  final List<double> widths = [];

  final Directory tempDir = await getTemporaryDirectory();
  final String tempPath = tempDir.path;

  for (EnteFile file in files) {
    if (file.fileType == FileType.livePhoto ||
        file.fileType == FileType.video) {
      continue;
    }

    final File? originalImage = await getFile(file);
    if (originalImage == null) continue;

    final List<int> bytes = await originalImage.readAsBytes();
    final img.Image? decodedImage = img.decodeImage(Uint8List.fromList(bytes));

    if (decodedImage != null) {
      String processedPath;

      if (_isJpegFile(originalImage.path)) {
        processedPath = originalImage.path;
      } else {
        processedPath =
            '$tempPath/${DateTime.now().millisecondsSinceEpoch}.jpg';
        File(
          processedPath,
        ).writeAsBytesSync(img.encodeJpg(decodedImage, quality: 95));
      }

      paths.add(processedPath);
      widths.add(decodedImage.width.toDouble());
      heights.add(decodedImage.height.toDouble());
    }
  }

  return ImageProcessingResult(paths: paths, heights: heights, widths: widths);
}

bool _isJpegFile(String path) {
  return path.toLowerCase().endsWith("jpg") ||
      path.toLowerCase().endsWith("jpeg");
}

Future<void> _executeFFmpegProcess({
  required BuildContext context,
  required String command,
  required Function onComplete,
}) async {
  try {
    final completer = Completer<void>();
    final startTime = DateTime.now().millisecondsSinceEpoch;

    await FFmpegKit.executeAsync(
      command,
      (session) async {
        final returnCode = await session.getReturnCode();
        final executionTime = _calculateExecutionTime(startTime);

        if (ReturnCode.isSuccess(returnCode)) {
          _logger.info(
            "FFmpeg command executed successfully in $executionTime seconds",
          );
          _completeOperation(completer, onComplete);
          if (!context.mounted) return;
          showToast(
            context,
            AppLocalizations.of(
              context,
            ).videoExportSuccess(path: _generateOutputPath()),
          );
        } else {
          _logger.warning(
            "FFmpeg process failed with return code $returnCode in $executionTime seconds",
          );
          _completeOperation(completer, onComplete);
          await FFmpegKit.cancel();
          if (!context.mounted) return;
          showToast(context, AppLocalizations.of(context).videoExportFailed);
        }
      },
      (log) {
        final String logMessage = log.getMessage();

        if (logMessage.contains("Invalid data found") ||
            logMessage.contains("Error")) {
          _logger.warning("Error detected in FFmpeg log: $logMessage");
          FFmpegKit.cancel();

          if (!completer.isCompleted) {
            _completeOperation(completer, onComplete);
          }
        }
      },
    );

    return completer.future;
  } catch (e) {
    await FFmpegKit.cancel();
    _logger.severe("Error during FFmpeg execution: $e");
    onComplete();
    rethrow;
  }
}

void _completeOperation(Completer<void> completer, Function onComplete) {
  onComplete();
  if (!completer.isCompleted) {
    completer.complete();
  }
}

double _calculateExecutionTime(int startTimeMs) {
  final endTime = DateTime.now().millisecondsSinceEpoch;
  return (endTime - startTimeMs) / 1000;
}

String _buildFFmpegCommand(
  BuildContext context,
  List<String> imagePaths,
  List<double> imageHeights,
  List<double> imageWidths,
) {
  final String outputPath = _generateOutputPath();

  final screenDimensions = MediaQuery.sizeOf(context);
  final int screenWidth = screenDimensions.width.toInt();
  final int screenHeight = screenDimensions.height.toInt();

  final StringBuffer command = StringBuffer();

  command.write('-y ');

  for (int i = 0; i < imagePaths.length; i++) {
    command.write('-loop 1 -t 2  -i "${imagePaths[i]}" ');
  }

  command.write('-filter_complex "');

  for (int i = 0; i < imagePaths.length; i++) {
    final double aspectRatioOfImage = imageWidths[i] / imageHeights[i];
    final double aspectRatioOfScreen = screenWidth / screenHeight;
    int scaledWidth, scaledHeight;

    if (aspectRatioOfImage > aspectRatioOfScreen) {
      scaledWidth = screenWidth;
      scaledHeight = (screenWidth / aspectRatioOfImage).toInt();
    } else {
      scaledHeight = screenHeight;
      scaledWidth = (screenHeight * aspectRatioOfImage).toInt();
    }

    command.write(
      '[$i:v]scale=$scaledWidth:$scaledHeight:force_original_aspect_ratio=decrease,'
      'pad=$screenWidth:$screenHeight:(ow-iw)/2:(oh-ih)/2,'
      'zoompan=z=\'zoom+0.001\':x=\'iw/2-(iw/zoom/2)\':y=\'ih/2-(ih/zoom/2)\':d=150:s=${screenWidth}x$screenHeight:fps=60[v$i];',
    );
  }

  for (int i = 0; i < imagePaths.length - 1; i++) {
    final String transition = _getTransitionType(i % 5);

    if (i == 0) {
      command.write(
        '[v0][v1]xfade=transition=$transition:duration=0.5:offset=2[f0];',
      );
    } else {
      command.write(
        '[f${i - 1}][v${i + 1}]xfade=transition=$transition:duration=0.5:offset=${2 * (i + 1)}[f$i];',
      );
    }
  }

  command.write(
    '" -map "[f${imagePaths.length - 2}]" '
    '-c:v libx264 -crf 18 -preset slow -movflags +faststart -pix_fmt yuv420p -r 60 '
    '-t ${imagePaths.length * 2} "$outputPath"',
  );

  return command.toString();
}

String _getTransitionType(int index) {
  switch (index) {
    case 0:
      return 'fade';
    case 1:
      return 'smoothleft';
    case 2:
      return 'smoothright';
    case 3:
      return 'slideright';
    default:
      return 'fadeblack';
  }
}

String _generateOutputPath() {
  Directory? directory;
  if (Platform.isAndroid) {
    try {
      directory = Directory('/storage/emulated/0/Download');
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
    } catch (e) {
      _logger.warning("Failed to create download directory: $e");
      directory = Directory('/storage/emulated/0/Download');
    }
  } else {
    directory = Directory('/storage/emulated/0/Download');
  }

  return '${directory.path}/ente_video_memory_${DateTime.now().millisecondsSinceEpoch}.mp4';
}

class ImageProcessingResult {
  final List<String> paths;
  final List<double> heights;
  final List<double> widths;

  ImageProcessingResult({
    required this.paths,
    required this.heights,
    required this.widths,
  });
}
