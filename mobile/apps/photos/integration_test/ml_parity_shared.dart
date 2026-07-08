import "dart:convert";
import "dart:io";

import "package:crypto/crypto.dart";
import "package:flutter_test/flutter_test.dart";
import "package:integration_test/integration_test.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:path_provider/path_provider.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/network/network.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/machine_learning/face_ml/face_detection/face_detection_service.dart";
import "package:photos/services/machine_learning/face_ml/face_embedding/face_embedding_service.dart";
import "package:photos/services/machine_learning/ml_indexing_isolate.dart";
import "package:photos/services/machine_learning/ml_model.dart";
import "package:photos/services/machine_learning/ml_result.dart";
import "package:photos/services/machine_learning/semantic_search/clip/clip_image_encoder.dart";
import "package:photos/utils/isolate/isolate_operations.dart";
import "package:shared_preferences/shared_preferences.dart";

const _manifestB64 = String.fromEnvironment("ML_PARITY_MANIFEST_B64");
const _codeRevision = String.fromEnvironment(
  "ML_PARITY_CODE_REVISION",
  defaultValue: "local",
);
const _localMirrorBaseUrl = String.fromEnvironment(
  "ML_PARITY_LOCAL_MIRROR_BASE_URL",
);
const _useLegacyMobileMl = bool.fromEnvironment(
  "ML_PARITY_USE_LEGACY_MOBILE_ML",
  defaultValue: false,
);
const _useRustMl = !_useLegacyMobileMl;
const _localModelMirrorRelativeDir = ".cache/local_model_mirror";

const _parityReportDataKey = "ml_parity_results_json";
const _modelBaseUrl = "https://models.ente.com/";
const _modelFiles = <String>[
  "yolov5s_face_640_640_dynamic.onnx",
  "mobilefacenet_opset15.onnx",
  "mobileclip_s2_image.onnx",
];

class _ManifestItem {
  final String fileID;
  final String sourceURL;
  final String? sourceSHA256;
  final String? sourcePath;

  const _ManifestItem({
    required this.fileID,
    required this.sourceURL,
    required this.sourceSHA256,
    required this.sourcePath,
  });
}

class _ModelSpec {
  final String schemaName;
  final MlModel model;

  const _ModelSpec({required this.schemaName, required this.model});
}

void runMLParityIntegrationTest({required String expectedPlatform}) {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    "ML parity runner ($expectedPlatform)",
    timeout: const Timeout(Duration(minutes: 45)),
    (tester) async {
      await tester.runAsync(() async {
        _validatePlatform(expectedPlatform);
        final manifestItems = _loadManifestItems();
        if (manifestItems.isEmpty) {
          throw StateError("Manifest is empty");
        }

        final appSupportDir = await getApplicationSupportDirectory();
        final fixtureRoot = Directory(
          "${appSupportDir.path}/ml_parity/fixtures",
        );
        await fixtureRoot.create(recursive: true);
        await _stageFixturesFromLocalMirror(
          manifestItems: manifestItems,
          fixtureRoot: fixtureRoot,
        );
        await _stageModelsFromLocalMirror(appSupportDir);

        final modelSpecs = _modelSpecs();
        final loadedModels = await _downloadAndLoadModels(
          modelSpecs: modelSpecs,
          loadLegacySessions: _useLegacyMobileMl,
        );

        final runtime = _useRustMl
            ? "rust-ml"
            : (Platform.isAndroid
                  ? "flutter-mobile-onnx-platform-plugin"
                  : "flutter-mobile-onnx-ffi");

        final results = <Map<String, dynamic>>[];
        final errors = <Map<String, dynamic>>[];
        try {
          for (int i = 0; i < manifestItems.length; i++) {
            final item = manifestItems[i];
            final stopwatch = Stopwatch()..start();
            try {
              final localFixturePath = await _downloadFixture(
                item: item,
                fixtureRoot: fixtureRoot,
              );
              final mlResult = await _analyzeImage(
                fileID: i + 1,
                filePath: localFixturePath,
                loadedModels: loadedModels,
              );
              stopwatch.stop();
              results.add(
                _toParityResult(
                  fileID: item.fileID,
                  mlResult: mlResult,
                  expectedPlatform: expectedPlatform,
                  runtime: runtime,
                  models: loadedModels.modelMetadata,
                  totalMS: stopwatch.elapsedMilliseconds,
                ),
              );
            } catch (error, stackTrace) {
              stopwatch.stop();
              final stackLines = stackTrace.toString().split("\n");
              errors.add({
                "file_id": item.fileID,
                "error": error.toString(),
                "timing_ms": stopwatch.elapsedMilliseconds,
                "stack": stackLines.isNotEmpty ? stackLines.first : "",
              });
            }
          }
        } finally {
          await _releaseModels(loadedModels);
        }

        final outputPayload = {
          "platform": expectedPlatform,
          "results": results,
          if (errors.isNotEmpty) "errors": errors,
        };

        binding.reportData = {_parityReportDataKey: jsonEncode(outputPayload)};
      });
    },
  );
}

void _validatePlatform(String expectedPlatform) {
  if (expectedPlatform == "android" && !Platform.isAndroid) {
    throw StateError("Android parity runner launched on non-Android platform");
  }
  if (expectedPlatform == "ios" && !Platform.isIOS) {
    throw StateError("iOS parity runner launched on non-iOS platform");
  }
}

List<_ManifestItem> _loadManifestItems() {
  if (_manifestB64.isEmpty) {
    throw StateError(
      "Missing ML_PARITY_MANIFEST_B64 dart define; run via infra/ml/test/run_ml_parity_tests.sh",
    );
  }
  final manifestBytes = base64Decode(_manifestB64);
  final manifest =
      jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
  final items = manifest["items"] as List<dynamic>? ?? const [];
  return items
      .map((dynamic rawItem) {
        final item = rawItem as Map<String, dynamic>;
        final sourceURL = (item["source_url"] as String?)?.trim() ?? "";
        if (sourceURL.isEmpty) {
          throw StateError(
            "Manifest item ${item["file_id"]} missing source_url",
          );
        }
        final sourceSHA = (item["source_sha256"] as String?)?.trim();
        final sourcePath = (item["source"] as String?)?.trim();
        return _ManifestItem(
          fileID: item["file_id"] as String,
          sourceURL: sourceURL,
          sourceSHA256: sourceSHA?.isEmpty == true ? null : sourceSHA,
          sourcePath: sourcePath?.isEmpty == true ? null : sourcePath,
        );
      })
      .toList(growable: false);
}

List<_ModelSpec> _modelSpecs() {
  return [
    _ModelSpec(
      schemaName: "face_detection",
      model: FaceDetectionService.instance,
    ),
    _ModelSpec(
      schemaName: "face_embedding",
      model: FaceEmbeddingService.instance,
    ),
    _ModelSpec(schemaName: "clip", model: ClipImageEncoder.instance),
  ];
}

class _LoadedModels {
  final List<String> modelNames;
  final List<int> modelAddresses;
  final Map<String, String> modelMetadata;
  final Map<String, String> modelPathsBySchema;

  const _LoadedModels({
    required this.modelNames,
    required this.modelAddresses,
    required this.modelMetadata,
    required this.modelPathsBySchema,
  });
}

Future<_LoadedModels> _downloadAndLoadModels({
  required List<_ModelSpec> modelSpecs,
  required bool loadLegacySessions,
}) async {
  await _ensureModelNetworkContext();

  final modelNames = <String>[];
  final modelPaths = <String>[];
  final modelMetadata = <String, String>{};
  final modelPathsBySchema = <String, String>{};

  for (final modelSpec in modelSpecs) {
    final (modelName, modelPath) = await modelSpec.model.getModelNameAndPath();
    final modelFile = File(modelPath);
    if (!modelFile.existsSync()) {
      throw StateError(
        "Resolved model path does not exist for $modelName: $modelPath",
      );
    }

    modelNames.add(modelName);
    modelPaths.add(modelFile.path);
    modelPathsBySchema[modelSpec.schemaName] = modelFile.path;
    final modelSHA256 = await _sha256HexOfFile(modelFile);
    modelMetadata[modelSpec.schemaName] =
        "${modelFile.uri.pathSegments.last}:$modelSHA256";
  }

  if (!loadLegacySessions) {
    return _LoadedModels(
      modelNames: modelNames,
      modelAddresses: const <int>[],
      modelMetadata: modelMetadata,
      modelPathsBySchema: modelPathsBySchema,
    );
  }

  final loadedAddressesRaw =
      await MLIndexingIsolate.instance.runInIsolate(
            IsolateOperation.loadIndexingModels,
            {"modelNames": modelNames, "modelPaths": modelPaths},
          )
          as List<dynamic>;

  final modelAddresses = loadedAddressesRaw
      .map((address) => (address as num).toInt())
      .toList(growable: false);
  if (modelAddresses.length != modelNames.length) {
    throw StateError(
      "Model address count mismatch: expected ${modelNames.length}, got ${modelAddresses.length}",
    );
  }

  return _LoadedModels(
    modelNames: modelNames,
    modelAddresses: modelAddresses,
    modelMetadata: modelMetadata,
    modelPathsBySchema: modelPathsBySchema,
  );
}

bool _modelNetworkContextInitialized = false;

Future<void> _ensureModelNetworkContext() async {
  if (_modelNetworkContextInitialized) {
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  final packageInfo = await PackageInfo.fromPlatform();
  await NetworkClient.instance.init(packageInfo, prefs);
  ServiceLocator.instance.init(
    prefs,
    NetworkClient.instance.enteDio,
    NetworkClient.instance.getDio(),
    NetworkClient.instance.downloadDio,
    packageInfo,
  );
  await Configuration.instance.init(prefs);
  _modelNetworkContextInitialized = true;
}

Future<void> _releaseModels(_LoadedModels loadedModels) async {
  if (loadedModels.modelAddresses.isEmpty) {
    return;
  }
  await MLIndexingIsolate.instance
      .runInIsolate(IsolateOperation.releaseIndexingModels, {
        "modelNames": loadedModels.modelNames,
        "modelAddresses": loadedModels.modelAddresses,
      });
}

Future<void> _stageFixturesFromLocalMirror({
  required List<_ManifestItem> manifestItems,
  required Directory fixtureRoot,
}) async {
  if (_localMirrorBaseUrl.isEmpty) {
    return;
  }

  for (final item in manifestItems) {
    final sourcePath = item.sourcePath;
    if (sourcePath == null || sourcePath.isEmpty) {
      continue;
    }

    final mirrorURL = _joinLocalMirrorUrl(sourcePath);
    final outputPath = "${fixtureRoot.path}/${_safeFileName(item.fileID)}";
    try {
      await _downloadURLToFile(url: mirrorURL, outputPath: outputPath);
    } catch (_) {
      // Local mirror is best-effort; fallback to source_url inside _downloadFixture.
    }
  }
}

Future<void> _stageModelsFromLocalMirror(Directory appSupportDir) async {
  if (_localMirrorBaseUrl.isEmpty) {
    return;
  }

  final assetsDir = Directory("${appSupportDir.path}/assets");
  await assetsDir.create(recursive: true);

  for (final modelFile in _modelFiles) {
    final canonicalURL = "$_modelBaseUrl$modelFile";
    final targetPath =
        "${assetsDir.path}/${_remoteAssetPathToLocalFileName(canonicalURL)}";
    final targetFile = File(targetPath);
    if (targetFile.existsSync()) {
      continue;
    }

    final mirrorURL = _joinLocalMirrorUrl(
      "$_localModelMirrorRelativeDir/$modelFile",
    );
    try {
      await _downloadURLToFile(url: mirrorURL, outputPath: targetPath);
    } catch (_) {
      // Local mirror is best-effort; model load falls back to default remote URL.
    }
  }
}

String _joinLocalMirrorUrl(String relativePath) {
  final sanitizedBase = _localMirrorBaseUrl.endsWith("/")
      ? _localMirrorBaseUrl
      : "$_localMirrorBaseUrl/";
  final encodedPath = relativePath
      .split("/")
      .where((segment) => segment.isNotEmpty)
      .map(Uri.encodeComponent)
      .join("/");
  return "$sanitizedBase$encodedPath";
}

String _remoteAssetPathToLocalFileName(String url) {
  var fileName = url
      .replaceAll(RegExp(r"https?://"), "")
      .replaceAll(RegExp(r"[^\w\.]"), "_");
  fileName = fileName.replaceAll(".", "_");
  return fileName;
}

Future<String> _downloadFixture({
  required _ManifestItem item,
  required Directory fixtureRoot,
}) async {
  final uri = Uri.parse(item.sourceURL);
  final outputPath = "${fixtureRoot.path}/${_safeFileName(item.fileID)}";
  final expectedSHA256 = item.sourceSHA256?.toLowerCase();

  Future<File> ensureFixture() async {
    final fixtureFile = await _downloadURLToFile(
      url: item.sourceURL,
      outputPath: outputPath,
    );
    if (expectedSHA256 == null) {
      return fixtureFile;
    }

    final actualSHA = (await _sha256HexOfFile(fixtureFile)).toLowerCase();
    if (actualSHA != expectedSHA256) {
      throw StateError(
        "Fixture SHA mismatch for ${item.fileID}: expected $expectedSHA256, got $actualSHA",
      );
    }
    return fixtureFile;
  }

  File fixtureFile;
  try {
    fixtureFile = await ensureFixture();
  } on StateError {
    final existingFile = File(outputPath);
    if (existingFile.existsSync()) {
      await existingFile.delete();
    }
    fixtureFile = await ensureFixture();
  }

  final fileNameFromURL = uri.pathSegments.isNotEmpty
      ? uri.pathSegments.last
      : "";
  if (fileNameFromURL.isEmpty) {
    return fixtureFile.path;
  }

  // Preserve extension semantics from source URL for decoder behavior parity.
  final extensionHint = fileNameFromURL.split(".").length > 1
      ? ".${fileNameFromURL.split(".").last}"
      : "";
  if (extensionHint.isEmpty || fixtureFile.path.endsWith(extensionHint)) {
    return fixtureFile.path;
  }

  final extensionPath = "${fixtureFile.path}$extensionHint";
  final extensionFile = File(extensionPath);
  if (extensionFile.existsSync()) {
    await extensionFile.delete();
  }
  await fixtureFile.copy(extensionPath);
  return extensionPath;
}

Future<File> _downloadURLToFile({
  required String url,
  required String outputPath,
}) async {
  final outputFile = File(outputPath);
  if (outputFile.existsSync()) {
    return outputFile;
  }

  await outputFile.parent.create(recursive: true);
  final tempPath = "$outputPath.tmp";
  final tempFile = File(tempPath);
  if (tempFile.existsSync()) {
    await tempFile.delete();
  }

  final httpClient = HttpClient();
  try {
    final request = await httpClient.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        "Failed to download $url: HTTP ${response.statusCode}",
        uri: Uri.parse(url),
      );
    }
    final sink = tempFile.openWrite();
    await response.pipe(sink);
    await sink.close();
    await tempFile.rename(outputPath);
  } finally {
    httpClient.close(force: true);
  }

  return outputFile;
}

Future<MLResult> _analyzeImage({
  required int fileID,
  required String filePath,
  required _LoadedModels loadedModels,
}) async {
  const useRustMl = _useRustMl;
  final args = <String, dynamic>{
    "enteFileID": fileID,
    "filePath": filePath,
    "runFaces": true,
    "runClip": true,
    "useRustMl": useRustMl,
  };

  if (useRustMl) {
    final faceDetectionModelPath =
        loadedModels.modelPathsBySchema["face_detection"];
    final faceEmbeddingModelPath =
        loadedModels.modelPathsBySchema["face_embedding"];
    final clipImageModelPath = loadedModels.modelPathsBySchema["clip"];
    if (faceDetectionModelPath == null ||
        faceEmbeddingModelPath == null ||
        clipImageModelPath == null) {
      throw StateError(
        "Missing model paths for Rust ML parity route: face_detection/face_embedding/clip",
      );
    }
    args.addAll({
      "faceDetectionModelPath": faceDetectionModelPath,
      "faceEmbeddingModelPath": faceEmbeddingModelPath,
      "clipImageModelPath": clipImageModelPath,
      "preferCoreml": Platform.isIOS,
      "preferNnapi": Platform.isAndroid,
      "preferXnnpack": Platform.isAndroid,
      "allowCpuFallback": true,
    });
  } else {
    if (loadedModels.modelAddresses.length < 3) {
      throw StateError(
        "Missing loaded model addresses for static parity route",
      );
    }
    final faceDetectionAddress = loadedModels.modelAddresses[0];
    final faceEmbeddingAddress = loadedModels.modelAddresses[1];
    final clipAddress = loadedModels.modelAddresses[2];
    args.addAll({
      "faceDetectionAddress": faceDetectionAddress,
      "faceEmbeddingAddress": faceEmbeddingAddress,
      "clipImageAddress": clipAddress,
    });
  }

  final resultJSONString =
      await MLIndexingIsolate.instance.runInIsolate(
            IsolateOperation.analyzeImage,
            args,
          )
          as String;
  return MLResult.fromJsonString(resultJSONString);
}

Map<String, dynamic> _toParityResult({
  required String fileID,
  required MLResult mlResult,
  required String expectedPlatform,
  required String runtime,
  required Map<String, String> models,
  required int totalMS,
}) {
  final clip = mlResult.clip;
  if (clip == null) {
    throw StateError("Missing CLIP result for $fileID");
  }

  final faces = (mlResult.faces ?? const <FaceResult>[])
      .map((face) {
        final box = face.detection.box;
        return {
          "box": [box[0], box[1], box[2] - box[0], box[3] - box[1]],
          "landmarks": face.detection.allKeypoints
              .map((point) => [point[0], point[1]])
              .toList(growable: false),
          "score": face.detection.score,
          "embedding": List<double>.from(face.embedding, growable: false),
        };
      })
      .toList(growable: false);

  return {
    "file_id": fileID,
    "clip": {"embedding": List<double>.from(clip.embedding, growable: false)},
    "faces": faces,
    "runner_metadata": {
      "platform": expectedPlatform,
      "runtime": runtime,
      "models": models,
      "code_revision": _codeRevision,
      "timing_ms": {"total": totalMS.toDouble()},
    },
  };
}

String _safeFileName(String value) {
  final sanitized = value.replaceAll(RegExp(r"[^a-zA-Z0-9._-]"), "_");
  if (sanitized.isNotEmpty) {
    return sanitized;
  }
  return "file";
}

Future<String> _sha256HexOfFile(File file) async {
  final digest = await sha256.bind(file.openRead()).first;
  return digest.toString();
}
