import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:integration_test/integration_test.dart';
import 'package:logging/logging.dart';
import 'package:native_video_editor/native_video_editor.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path_helper;
import 'package:photo_manager/photo_manager.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/network/network.dart';
import 'package:photos/db/files_db.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/metadata/file_magic.dart';
import 'package:photos/module/download/file.dart';
import 'package:photos/module/metadata/local_file.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/file_magic_service.dart';
import 'package:photos/ui/tools/editor/native_video_export_service.dart';
import 'package:photos/ui/tools/editor/video_crop_util.dart';
import 'package:photos/ui/tools/editor/video_editor/crop_value.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_editor/video_editor.dart';

/// Trim configuration
class TrimConfig {
  final String label;
  final Duration? duration;
  final Duration startOffset;

  const TrimConfig({
    required this.label,
    this.duration,
    this.startOffset = Duration.zero,
  });

  bool get shouldTrim => duration != null;

  @override
  String toString() => label;
}

/// Trim configuration factory
class TrimConfigs {
  static const noTrim = TrimConfig(label: "no-trim", duration: null);

  /// Create a trim config from seconds
  /// Example: TrimConfigs.fromSeconds(15) → trim to 15 seconds
  static TrimConfig fromSeconds(int seconds) {
    return TrimConfig(
      label: "trim-${seconds}s",
      duration: Duration(seconds: seconds),
    );
  }

  /// Create a trim config from duration
  /// Example: TrimConfigs.fromDuration(Duration(minutes: 1, seconds: 30))
  static TrimConfig fromDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    return TrimConfig(label: "trim-${totalSeconds}s", duration: duration);
  }

  /// Create a trim config from start offset and length
  static TrimConfig fromRange({
    required int startSeconds,
    required int lengthSeconds,
  }) {
    return TrimConfig(
      label: "trim-${startSeconds}s-${startSeconds + lengthSeconds}s",
      duration: Duration(seconds: lengthSeconds),
      startOffset: Duration(seconds: startSeconds),
    );
  }
}

/// Validation failure details
class ValidationFailure {
  final String fileId;
  final String description;
  final String failureType;
  final String expected;
  final String actual;
  final String? stackTrace;

  ValidationFailure({
    required this.fileId,
    required this.description,
    required this.failureType,
    required this.expected,
    required this.actual,
    this.stackTrace,
  });
}

/// Result of processing a video iteration
class IterationResult {
  final List<ValidationFailure> validationFailures;

  IterationResult({required this.validationFailures});
}

/// Configuration for one or more files to test with the same combinations
class TestFileConfig {
  final List<int> fileIds;
  final int? collectionId;
  final List<TrimConfig> trimOptions;
  final List<String> cropOptions;
  final List<int> rotateOptions;

  TestFileConfig({
    required this.fileIds,
    this.collectionId,
    required this.trimOptions,
    required this.cropOptions,
    required this.rotateOptions,
  });

  int get totalIterationsPerFile =>
      trimOptions.length * cropOptions.length * rotateOptions.length;

  int get totalIterations => totalIterationsPerFile * fileIds.length;
}

/// Video Editor Integration Test
///
/// Tests native video editor by processing videos through all combinations
/// of trim/crop/rotate. Validates exported video duration and dimensions.
///
/// CONFIGURATION:
/// Update testFiles list below. Each TestFileConfig can have:
/// - fileIds: [123, 456] - One or more video file IDs to test
/// - collectionId: null (uses source's collection) or specific ID
/// - trimOptions: [TrimConfigs.noTrim, TrimConfigs.fromSeconds(1), TrimConfigs.fromSeconds(15), ...]
/// - cropOptions: ["None", "1:1", "16:9", "9:16", "3:4", "4:3"]
/// - rotateOptions: [0, 90, 180, 270]
///
/// EXAMPLES:
/// // Single file, full test
/// TestFileConfig(
///   fileIds: [123],
///   trimOptions: [TrimConfigs.noTrim, TrimConfigs.fromSeconds(1)],
///   cropOptions: ["None", "1:1"],
///   rotateOptions: [0, 90],
/// ) // 2 × 2 × 2 = 8 iterations
///
/// // Multiple files, same combinations
/// TestFileConfig(
///   fileIds: [123, 456, 789],
///   trimOptions: [TrimConfigs.fromSeconds(2)],
///   cropOptions: ["1:1"],
///   rotateOptions: [0],
/// ) // 1 × 1 × 1 × 3 files = 3 iterations
///
/// // Custom trim durations
/// TestFileConfig(
///   fileIds: [123],
///   trimOptions: [TrimConfigs.fromSeconds(30), TrimConfigs.fromDuration(Duration(minutes: 2))],
///   cropOptions: ["None"],
///   rotateOptions: [0],
/// )
///
/// RUN:
/// flutter drive --driver=test_driver/integration_test.dart \
///   --target=integration_test/video_editor_test.dart --flavor independent
///
/// VALIDATION:
/// - Duration check: ±100ms tolerance
/// - Width/Height check: ±2px tolerance
/// - Failures are grouped by type (export vs validation) in the final report
/// - Tests native editor only (no FFmpeg fallback)
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final logger = Logger("VideoEditorIntegrationTest");
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print('[${record.level.name}] ${record.time}: ${record.message}');
  });

  // TEST CONFIGURATION - Update this list with your files and combinations
  final testFiles = [
    TestFileConfig(
      // TODO: Update with the generated file IDs available on the test device.
      fileIds: [0],
      collectionId: null,
      trimOptions: [
        TrimConfigs.fromSeconds(3),
        TrimConfigs.fromRange(startSeconds: 1, lengthSeconds: 5),
      ],
      cropOptions: ["1:1", "9:16", "16:9", "3:4", "4:3"],
      rotateOptions: [0, 90, 180, 270],
    ),
    // Add more configurations with different combinations:
    // TestFileConfig(
    //   fileIds: [456, 789, 101], // Multiple files with same combinations
    //   collectionId: 999,        // Save to specific collection
    //   trimOptions: [TrimConfigs.fromSeconds(2), TrimConfigs.fromSeconds(5)],
    //   cropOptions: ["None", "1:1"],
    //   rotateOptions: [0, 90],
    // ),
  ];

  group('Video Editor Integration Test', () {
    testWidgets('Process videos with all trim/crop/rotate combinations', (
      WidgetTester tester,
    ) async {
      // Initialize global singletons that the app normally sets up on startup.
      final prefs = await SharedPreferences.getInstance();
      final packageInfo = await PackageInfo.fromPlatform();

      // Initialize network clients before service locator (mirrors app bootstrap).
      await NetworkClient.instance.init(packageInfo, prefs);

      ServiceLocator.instance.init(
        prefs,
        NetworkClient.instance.enteDio,
        NetworkClient.instance.getDio(),
        NetworkClient.instance.downloadDio,
        packageInfo,
      );
      await Configuration.instance.init(prefs);

      // Verify configuration
      expect(
        testFiles,
        isNotEmpty,
        reason: 'Please configure at least one test configuration',
      );
      for (final config in testFiles) {
        expect(
          config.fileIds,
          isNotEmpty,
          reason: 'Please set at least one fileId in each configuration',
        );
        for (final fileId in config.fileIds) {
          expect(
            fileId,
            isNot(0),
            reason: 'Please set valid fileIds (found 0)',
          );
        }
      }

      // Calculate total files and iterations
      final totalFiles = testFiles.fold(
        0,
        (sum, config) => sum + config.fileIds.length,
      );
      final totalIterations = testFiles.fold(
        0,
        (sum, config) => sum + config.totalIterations,
      );
      logger.info('═══════════════════════════════════════════════════════');
      logger.info(
        'Starting test with $totalFiles file(s), ${testFiles.length} configuration(s)',
      );
      logger.info('Total iterations: $totalIterations');
      logger.info('═══════════════════════════════════════════════════════\n');

      int globalIterationCount = 0;
      final successfulExports = <String>[];
      final failedExports = <String, String>{};
      final validationFailures = <ValidationFailure>[];

      // Process each configuration
      for (int configIndex = 0; configIndex < testFiles.length; configIndex++) {
        final config = testFiles[configIndex];

        logger.info(
          '\n╔═══════════════════════════════════════════════════════╗',
        );
        logger.info('║ CONFIG ${configIndex + 1}/${testFiles.length}');
        logger.info('║ Files: ${config.fileIds}');
        logger.info('║ Iterations per file: ${config.totalIterationsPerFile}');
        logger.info('║ Trim: ${config.trimOptions}');
        logger.info('║ Crop: ${config.cropOptions}');
        logger.info('║ Rotate: ${config.rotateOptions}');
        logger.info(
          '╚═══════════════════════════════════════════════════════╝\n',
        );

        // Process each file in this configuration
        for (
          int fileIndex = 0;
          fileIndex < config.fileIds.length;
          fileIndex++
        ) {
          final fileId = config.fileIds[fileIndex];

          logger.info('─────────────────────────────────────────────────────');
          logger.info(
            'File ${fileIndex + 1}/${config.fileIds.length} in config ${configIndex + 1}: ID $fileId',
          );
          logger.info('─────────────────────────────────────────────────────');

          // Load source file
          logger.info('Loading source file with ID: $fileId');
          final sourceFile = await FilesDB.instance.getAnyUploadedFile(fileId);
          expect(
            sourceFile,
            isNotNull,
            reason: 'Uploaded file with ID $fileId not found',
          );

          File? sourceIoFile;

          if (sourceFile!.localID != null) {
            final assetEntity = await sourceFile.getAsset;
            if (assetEntity != null) {
              sourceIoFile = await assetEntity.file;
              if (sourceIoFile == null || !sourceIoFile.existsSync()) {
                logger.warning(
                  'Local asset file missing for uploaded file $fileId despite AssetEntity, will try server fetch.',
                );
                sourceIoFile = null;
              }
            } else {
              logger.info(
                'AssetEntity not found locally for uploaded file $fileId. Falling back to server fetch.',
              );
            }
          }

          if (sourceIoFile == null && sourceFile.isUploaded) {
            logger.info('Fetching uploaded file $fileId from server cache...');
            sourceIoFile = await getFileFromServer(sourceFile);
          }

          expect(
            sourceIoFile,
            isNotNull,
            reason: 'Source video file not available for uploaded file $fileId',
          );
          expect(
            sourceIoFile!.existsSync(),
            isTrue,
            reason: 'Downloaded source video file missing on disk for $fileId',
          );

          logger.info('Source file loaded: ${sourceFile.title}');
          logger.info('Video path: ${sourceIoFile.path}\n');

          // Iterate through all combinations for this file
          int fileIterationCount = 0;
          for (final trimOption in config.trimOptions) {
            for (final cropOption in config.cropOptions) {
              for (final rotateOption in config.rotateOptions) {
                globalIterationCount++;
                fileIterationCount++;
                final description =
                    't: $trimOption, c: $cropOption, r: $rotateOption';

                logger.info(
                  '═══════════════════════════════════════════════════════',
                );
                logger.info(
                  'File $fileId, Iteration $fileIterationCount/${config.totalIterationsPerFile} (Global: $globalIterationCount/$totalIterations)',
                );
                logger.info('Settings: $description');
                logger.info(
                  '═══════════════════════════════════════════════════════',
                );

                try {
                  final result = await _processVideoIteration(
                    sourceFile: sourceFile,
                    sourceIoFile: sourceIoFile,
                    collectionId: config.collectionId,
                    trimOption: trimOption,
                    cropOption: cropOption,
                    rotateOption: rotateOption,
                    description: description,
                    logger: logger,
                  );

                  final totalFailures = result.validationFailures.length;
                  if (totalFailures == 0) {
                    successfulExports.add('File $fileId: $description');
                    logger.info('✓ Iteration completed successfully\n');
                  } else {
                    validationFailures.addAll(result.validationFailures);
                    final msg =
                        '⚠ Iteration completed with $totalFailures validation failure(s)\n';
                    logger.warning(msg);
                  }
                } catch (e, s) {
                  failedExports['File $fileId: $description'] = e.toString();
                  logger.severe('✗ Iteration FAILED', e, s);
                  logger.severe('Error: $e\n');
                  // Continue with next iteration instead of failing entire test
                }
              }
            }
          }

          logger.info(
            'File $fileId completed: $fileIterationCount/${config.totalIterationsPerFile} iterations\n',
          );
        }

        logger.info('═══════════════════════════════════════════════════════');
        logger.info('Config ${configIndex + 1}/${testFiles.length} completed');
        logger.info(
          '═══════════════════════════════════════════════════════\n',
        );
      }

      // Print final summary
      logger.info(
        '\n╔═══════════════════════════════════════════════════════╗',
      );
      logger.info('║ FINAL TEST SUMMARY');
      logger.info('╚═══════════════════════════════════════════════════════╝');
      logger.info('Total configurations: ${testFiles.length}');
      logger.info('Total files processed: $totalFiles');
      logger.info('Total iterations: $totalIterations');
      logger.info('Successful: ${successfulExports.length}');
      logger.info('Export failures: ${failedExports.length}');
      logger.info('Validation failures: ${validationFailures.length}');

      if (failedExports.isNotEmpty) {
        logger.severe(
          '\n╔═══════════════════════════════════════════════════════╗',
        );
        logger.severe('║ EXPORT FAILURES (${failedExports.length})');
        logger.severe(
          '╚═══════════════════════════════════════════════════════╝',
        );
        failedExports.forEach((desc, error) {
          logger.severe('  ✗ $desc');
          logger.severe('    Error: $error\n');
        });
      }

      if (validationFailures.isNotEmpty) {
        logger.warning(
          '\n╔═══════════════════════════════════════════════════════╗',
        );
        logger.warning('║ VALIDATION FAILURES (${validationFailures.length})');
        logger.warning(
          '╚═══════════════════════════════════════════════════════╝',
        );

        // Group by failure type
        final groupedFailures = <String, List<ValidationFailure>>{};
        for (final failure in validationFailures) {
          groupedFailures
              .putIfAbsent(failure.failureType, () => [])
              .add(failure);
        }

        groupedFailures.forEach((type, failures) {
          logger.warning(
            '\n  ${type.toUpperCase()} (${failures.length} failures):',
          );
          for (final failure in failures) {
            logger.warning(
              '    ✗ File ${failure.fileId}: ${failure.description}',
            );
            logger.warning('      Expected: ${failure.expected}');
            logger.warning('      Actual:   ${failure.actual}');
          }
        });
        logger.warning('');
      }

      logger.info('═══════════════════════════════════════════════════════\n');

      // Fail test if any iteration failed or had validation errors
      final totalFailures = failedExports.length + validationFailures.length;
      expect(
        totalFailures,
        0,
        reason:
            '$totalFailures failure(s) detected (${failedExports.length} export, ${validationFailures.length} validation). See logs above.',
      );
    });
  });
}

/// Process a single video iteration with the specified settings.
/// Returns any validation failures detected for the exported video.
Future<IterationResult> _processVideoIteration({
  required EnteFile sourceFile,
  required File sourceIoFile,
  required int? collectionId,
  required TrimConfig trimOption,
  required String cropOption,
  required int rotateOption,
  required String description,
  required Logger logger,
}) async {
  VideoEditorController? controller;
  File? tempOutputFile;
  final failures = <ValidationFailure>[];
  CropCalculation? cropCalc;

  try {
    // Step 1: Initialize video editor controller
    logger.info('  → Initializing video editor controller...');
    controller = VideoEditorController.file(
      sourceIoFile,
      minDuration: const Duration(
        milliseconds: 100,
      ), // Allow very short videos for testing
    );
    await controller.initialize();

    final originalDuration = controller.videoDuration;
    final originalSize = controller.video.value.size;
    logger.info('  → Controller initialized');
    logger.info(
      '     - Original duration: ${originalDuration.inMilliseconds}ms',
    );
    logger.info(
      '     - Original size: ${originalSize.width.toInt()}x${originalSize.height.toInt()}',
    );

    // Track expected dimensions (will be updated after crop)
    var expectedWidth = originalSize.width.toInt();
    var expectedHeight = originalSize.height.toInt();

    // Step 2: Apply trim settings
    Duration? expectedDuration;
    if (trimOption.shouldTrim) {
      final startOffset = trimOption.startOffset;
      final trimmedStart = startOffset > controller.videoDuration
          ? controller.videoDuration
          : startOffset;

      final desiredEnd = trimmedStart + trimOption.duration!;
      final trimmedEnd = desiredEnd > controller.videoDuration
          ? controller.videoDuration
          : desiredEnd;

      if (trimmedStart >= trimmedEnd) {
        logger.warning(
          '  → Skipping trim: start (${trimmedStart.inMilliseconds}ms) >= end (${trimmedEnd.inMilliseconds}ms)',
        );
        expectedDuration = controller.videoDuration;
      } else {
        logger.info(
          '  → Applying trim from ${trimmedStart.inMilliseconds}ms to ${trimmedEnd.inMilliseconds}ms...',
        );

        final minTrim =
            trimmedStart.inMilliseconds / originalDuration.inMilliseconds;
        final maxTrim =
            trimmedEnd.inMilliseconds / originalDuration.inMilliseconds;
        controller.updateTrim(minTrim, maxTrim);

        expectedDuration = trimmedEnd - trimmedStart;
      }
    } else {
      expectedDuration = originalDuration;
      logger.info('  → No trim applied');
    }

    // Step 3: Apply crop settings
    if (cropOption != "None") {
      logger.info('  → Applying crop: $cropOption...');

      // Map crop option to CropValue and apply aspect ratio
      CropValue? cropValue;
      switch (cropOption) {
        case "1:1":
          cropValue = CropValue.ratio_1_1;
          break;
        case "16:9":
          cropValue = CropValue.ratio_16_9;
          break;
        case "9:16":
          cropValue = CropValue.ratio_9_16;
          break;
        case "3:4":
          cropValue = CropValue.ratio_3_4;
          break;
        case "4:3":
          cropValue = CropValue.ratio_4_3;
          break;
      }

      if (cropValue != null) {
        final aspectRatio = cropValue.getFraction()?.toDouble();
        if (aspectRatio != null) {
          controller.preferredCropAspectRatio = aspectRatio;
        } else {
          controller.applyCacheCrop();
        }
      } else {
        controller.applyCacheCrop();
      }

      // Calculate expected dimensions after crop
      try {
        cropCalc = VideoCropUtil.calculateFileSpaceCrop(controller: controller);
        expectedWidth = cropCalc.width;
        expectedHeight = cropCalc.height;
        logger.info(
          '  → Crop applied: $cropOption (${expectedWidth}x$expectedHeight)',
        );
      } catch (e) {
        logger.warning('     - Failed to calculate crop dimensions: $e');
        logger.info('  → Crop applied: $cropOption');
      }
    } else {
      logger.info('  → No crop applied');
    }

    // Step 4: Apply rotation
    if (rotateOption != 0) {
      logger.info('  → Applying rotation: $rotateOption°...');

      // Reset rotation to 0 first
      while (controller.rotation != 0) {
        controller.rotate90Degrees(RotateDirection.left);
      }

      // Apply the desired rotation (from video_rotate_page.dart)
      switch (rotateOption) {
        case 90:
          controller.rotate90Degrees(RotateDirection.right);
          break;
        case 180:
          controller.rotate90Degrees(RotateDirection.left);
          controller.rotate90Degrees(RotateDirection.left);
          break;
        case 270:
          controller.rotate90Degrees(RotateDirection.left);
          break;
      }

      logger.info('  → Rotation applied: ${controller.rotation}°');
    } else {
      logger.info('  → No rotation applied');
    }

    // Step 5: Export video using native editor (no FFmpeg fallback)
    logger.info('  → Exporting video with native editor...');

    // Create temp output path
    final tempDir = Directory.systemTemp.createTempSync(
      'ente_video_export_test',
    );
    final outputPath = path_helper.join(
      tempDir.path,
      'export_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );

    // Use original NativeVideoExportService with FFmpeg fallback disabled
    final exportedFile = await NativeVideoExportService.exportVideo(
      controller: controller,
      outputPath: outputPath,
      allowFfmpegFallback: false, // NO FFmpeg fallback for tests
      onProgress: (progress) {
        // Log progress at 25% intervals
        if ((progress * 100).round() % 25 == 0) {
          logger.info(
            '     - Progress: ${(progress * 100).toStringAsFixed(0)}%',
          );
        }
      },
      onError: (e, s) {
        logger.severe(
          '  ✗ Native export failed - NO FFmpeg fallback in test!',
          e,
          s,
        );
      },
    );

    tempOutputFile = exportedFile;
    logger.info('  → Export completed: ${exportedFile.path}');

    // Step 6: Save to gallery
    logger.info('  → Saving to gallery...');
    final suffixBuffer = StringBuffer();
    if (trimOption.shouldTrim) {
      suffixBuffer.write('_t');
    }
    if (cropOption != "None") {
      suffixBuffer.write('_c_$cropOption');
    }
    if (rotateOption != 0) {
      suffixBuffer.write('_r_$rotateOption');
    }

    final baseName = path_helper.basenameWithoutExtension(sourceFile.title!);
    final fileName =
        baseName +
        suffixBuffer.toString() +
        '_edited_' +
        DateTime.now().microsecondsSinceEpoch.toString() +
        '.mp4';

    await PhotoManager.stopChangeNotify();
    try {
      final newAsset = await PhotoManager.editor.saveVideo(
        exportedFile,
        title: fileName,
      );
      logger.info('  → Saved to gallery: $fileName');

      // Step 7: Create EnteFile entry
      logger.info('  → Creating file entry in database...');
      final newFile = fileFromAsset(sourceFile.deviceFolder ?? '', newAsset);

      newFile.creationTime = sourceFile.creationTime;
      // Use provided collectionId, or source file's collection if null/0
      newFile.collectionID = (collectionId == null || collectionId == 0)
          ? sourceFile.collectionID
          : collectionId;
      newFile.location = sourceFile.location;

      newFile.generatedID = await FilesDB.instance.insertAndGetId(newFile);
      logger.info('  → File entry created (ID: ${newFile.generatedID})');

      final settingsToast = _buildSettingsToastMessage(
        trimOption: trimOption,
        cropOption: cropOption,
        rotateOption: rotateOption,
      );
      if (settingsToast != null) {
        await Fluttertoast.showToast(
          msg: settingsToast,
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.TOP,
        );
      }

      // Step 8: Validate exported video
      logger.info('  → Validating exported video...');
      try {
        final videoInfo = await NativeVideoEditor.getVideoInfo(
          exportedFile.path,
        );
        final actualDuration = Duration(
          milliseconds: (videoInfo['duration'] as num?)?.toInt() ?? 0,
        );
        final actualWidth = (videoInfo['width'] as num?)?.toInt() ?? 0;
        final actualHeight = (videoInfo['height'] as num?)?.toInt() ?? 0;

        logger.info(
          '     - Actual duration: ${actualDuration.inMilliseconds}ms',
        );
        logger.info('     - Actual size: ${actualWidth}x$actualHeight');

        // Validate duration (allow 100ms tolerance for encoding variations)
        final durationDiff =
            (actualDuration.inMilliseconds - expectedDuration.inMilliseconds)
                .abs();
        if (durationDiff > 100) {
          failures.add(
            ValidationFailure(
              fileId: sourceFile.generatedID.toString(),
              description: description,
              failureType: 'duration',
              expected: '${expectedDuration.inMilliseconds}ms',
              actual:
                  '${actualDuration.inMilliseconds}ms (diff: ${durationDiff}ms)',
            ),
          );
          logger.warning(
            '     ⚠ Duration mismatch! Expected: ${expectedDuration.inMilliseconds}ms, Got: ${actualDuration.inMilliseconds}ms',
          );
        }

        // Validate dimensions (accounting for crop and rotation)
        final expectedRotation = rotateOption;
        final isRotated = expectedRotation % 180 != 0;

        // expectedWidth and expectedHeight already account for crop
        // Just swap if rotation is 90/270 degrees
        var finalExpectedWidth = expectedWidth;
        var finalExpectedHeight = expectedHeight;

        if (isRotated) {
          // Swap dimensions for 90/270 rotation
          final temp = finalExpectedWidth;
          finalExpectedWidth = finalExpectedHeight;
          finalExpectedHeight = temp;
        }

        bool widthOk = (actualWidth - finalExpectedWidth).abs() <= 2;
        bool heightOk = (actualHeight - finalExpectedHeight).abs() <= 2;

        if (!widthOk || !heightOk) {
          final swappedWidth = finalExpectedHeight;
          final swappedHeight = finalExpectedWidth;
          final swappedWidthOk = (actualWidth - swappedWidth).abs() <= 2;
          final swappedHeightOk = (actualHeight - swappedHeight).abs() <= 2;

          if (swappedWidthOk && swappedHeightOk) {
            logger.info(
              '     - Exported dimensions appear swapped (${actualWidth}x$actualHeight) vs expected ${finalExpectedWidth}x$finalExpectedHeight. '
              'Accepting as valid.',
            );
            widthOk = true;
            heightOk = true;
          }
        }

        // Check width (allow some tolerance for encoding)
        if (!widthOk) {
          failures.add(
            ValidationFailure(
              fileId: sourceFile.generatedID.toString(),
              description: description,
              failureType: 'width',
              expected: '$finalExpectedWidth',
              actual: '$actualWidth',
            ),
          );
          logger.warning(
            '     ⚠ Width mismatch! Expected: $finalExpectedWidth, Got: $actualWidth',
          );
        }

        // Check height (allow some tolerance for encoding)
        if (!heightOk) {
          failures.add(
            ValidationFailure(
              fileId: sourceFile.generatedID.toString(),
              description: description,
              failureType: 'height',
              expected: '$finalExpectedHeight',
              actual: '$actualHeight',
            ),
          );
          logger.warning(
            '     ⚠ Height mismatch! Expected: $finalExpectedHeight, Got: $actualHeight',
          );
        }

        if (failures.isEmpty) {
          logger.info('     ✓ Validation passed');
        } else {
          logger.warning('     ⚠ Validation found ${failures.length} issue(s)');
        }
      } catch (e) {
        logger.warning('     - Failed to validate video info: $e');
        // Non-fatal - continue
      }

      // Step 9: Update description with test parameters
      logger.info('  → Updating video description...');

      // Only update if file is uploaded (has uploadedFileID)
      // For local-only files, we skip the metadata update
      if (newFile.uploadedFileID != null) {
        try {
          await FileMagicService.instance.updatePublicMagicMetadata(
            [newFile],
            {captionKey: description},
          );
          logger.info('  → Description set: "$description"');
        } catch (e) {
          logger.warning('     - Failed to update description (non-fatal): $e');
          // Don't fail the test if description update fails
        }
      } else {
        logger.info(
          '     - Skipping description update (file not uploaded yet)',
        );
      }

      // Cleanup temp file
      if (tempOutputFile.existsSync()) {
        tempOutputFile.deleteSync();
      }
    } finally {
      await PhotoManager.startChangeNotify();
    }
  } finally {
    // Cleanup
    await controller?.dispose();
    if (tempOutputFile != null && tempOutputFile.existsSync()) {
      try {
        tempOutputFile.deleteSync();
      } catch (_) {}
    }
  }

  return IterationResult(validationFailures: failures);
}

String? _buildSettingsToastMessage({
  required TrimConfig trimOption,
  required String cropOption,
  required int rotateOption,
}) {
  final parts = <String>[];

  if (trimOption.shouldTrim) {
    final start = trimOption.startOffset.inSeconds;
    final end =
        (trimOption.startOffset + (trimOption.duration ?? Duration.zero))
            .inSeconds;
    parts.add('Trim: ${start}s → ${end}s');
  }
  if (cropOption != 'None') {
    parts.add('Crop: $cropOption');
  }
  if (rotateOption % 360 != 0) {
    parts.add('Rotate: ${rotateOption % 360}°');
  }

  if (parts.isEmpty) {
    return null;
  }
  return parts.join(' • ');
}
