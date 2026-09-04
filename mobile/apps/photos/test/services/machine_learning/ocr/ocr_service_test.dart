import "dart:io";

import "package:flutter/widgets.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/services/machine_learning/ocr/ocr_backend.dart";
import "package:photos/services/machine_learning/ocr/ocr_models.dart";
import "package:photos/services/machine_learning/ocr_service.dart";

class _FakeBackend implements OcrBackend {
  _FakeBackend(this.name);

  final String name;
  final List<String> calls = [];
  Set<OcrModelComponent>? preparedComponents;

  @override
  Future<ModelPreparationStatus> prepareModels(
    Set<OcrModelComponent> components,
  ) async {
    calls.add("prepareModels");
    preparedComponents = components;
    return ModelPreparationStatus(isReady: true, version: name);
  }

  @override
  Future<TextDetectionResult> detectText({
    required String imagePath,
    bool includeAllConfidenceScores = false,
    String? requestId,
  }) async {
    calls.add("detectText:$requestId:$includeAllConfidenceScores");
    return const TextDetectionResult(blocks: [], imageSize: Size(1, 1));
  }

  @override
  Future<TextRegionDetectionResult> detectTextRegions({
    required String imagePath,
    String? requestId,
  }) async {
    calls.add("detectTextRegions:$requestId");
    return const TextRegionDetectionResult(regions: [], imageSize: Size(1, 1));
  }

  @override
  Future<void> cancelRequest(String requestId) async {
    calls.add("cancelRequest:$requestId");
  }

  @override
  Future<String> ensureDisplayablePath(String imagePath) async {
    calls.add("ensureDisplayablePath");
    return "$name:$imagePath";
  }
}

class _Harness {
  _Harness({
    required bool rustOcr,
    required bool isAndroid,
    required bool isIOS,
  }) : rustOcr = rustOcr {
    service = OcrService(
      rustOcrEnabled: () => this.rustOcr,
      isAndroid: isAndroid,
      isIOS: isIOS,
      createLegacyBackend: () => _create(legacy),
      createRustBackend: () => _create(rust),
      createVisionBackend: () => _create(vision),
    );
  }

  bool rustOcr;
  late final OcrService service;
  final legacy = _FakeBackend("legacy");
  final rust = _FakeBackend("rust");
  final vision = _FakeBackend("vision");
  final created = <String>[];

  OcrBackend _create(_FakeBackend backend) {
    created.add(backend.name);
    return backend;
  }
}

void main() {
  late Directory tempDirectory;
  late String imagePath;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp("ocr_service_test");
    imagePath = "${tempDirectory.path}/photo.jpg";
    await File(imagePath).writeAsBytes(const [1, 2, 3]);
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  test("uses the Rust backend on Android when the flag is on", () async {
    final harness = _Harness(rustOcr: true, isAndroid: true, isIOS: false);

    expect(harness.service.backendKind, OcrBackendKind.rust);
    final status = await harness.service.prepareModels();
    expect(status.version, "rust");
    expect(harness.rust.preparedComponents, OcrModelComponent.values.toSet());
    expect(harness.created, ["rust"]);
  });

  test("uses the Vision backend on iOS when the flag is on", () async {
    final harness = _Harness(rustOcr: true, isAndroid: false, isIOS: true);

    expect(harness.service.backendKind, OcrBackendKind.vision);
    final status = await harness.service.prepareModels(
      components: {OcrModelComponent.detector},
    );
    expect(status.version, "vision");
    expect(harness.vision.preparedComponents, {OcrModelComponent.detector});
    expect(harness.created, ["vision"]);
  });

  test("uses the legacy backend when the flag is off", () async {
    for (final (isAndroid, isIOS) in const [(true, false), (false, true)]) {
      final harness = _Harness(
        rustOcr: false,
        isAndroid: isAndroid,
        isIOS: isIOS,
      );

      expect(harness.service.backendKind, OcrBackendKind.legacy);
      await harness.service.cancelRequest("r");
      expect(harness.legacy.calls, ["cancelRequest:r"]);
      expect(harness.created, ["legacy"]);
    }
  });

  test("uses the legacy backend on other platforms even with the flag on", () {
    final harness = _Harness(rustOcr: true, isAndroid: false, isIOS: false);

    expect(harness.service.backendKind, OcrBackendKind.legacy);
  });

  test("pins the backend chosen on first use", () async {
    final harness = _Harness(rustOcr: false, isAndroid: true, isIOS: false);

    await harness.service.cancelRequest("a");
    harness.rustOcr = true;
    await harness.service.cancelRequest("b");

    expect(harness.legacy.calls, ["cancelRequest:a", "cancelRequest:b"]);
    expect(harness.rust.calls, isEmpty);
    expect(harness.created, ["legacy"]);
  });

  test("detectText forwards to the backend for an existing image", () async {
    final harness = _Harness(rustOcr: true, isAndroid: true, isIOS: false);

    final result = await harness.service.detectText(
      imagePath: imagePath,
      includeAllConfidenceScores: true,
      requestId: "r1",
    );

    expect(result.imageSize, const Size(1, 1));
    expect(harness.rust.calls, ["detectText:r1:true"]);
  });

  test(
    "detectTextRegions forwards to the backend for an existing image",
    () async {
      final harness = _Harness(rustOcr: true, isAndroid: false, isIOS: true);

      await harness.service.detectTextRegions(
        imagePath: imagePath,
        requestId: "r2",
      );

      expect(harness.vision.calls, ["detectTextRegions:r2"]);
    },
  );

  test("rejects a missing image before reaching the backend", () async {
    final harness = _Harness(rustOcr: true, isAndroid: true, isIOS: false);
    final missingPath = "${tempDirectory.path}/missing.jpg";

    await expectLater(
      harness.service.detectText(imagePath: missingPath),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          "message",
          "Image file does not exist at path: $missingPath",
        ),
      ),
    );
    await expectLater(
      harness.service.detectTextRegions(imagePath: missingPath),
      throwsArgumentError,
    );
    expect(harness.rust.calls, isEmpty);
    expect(harness.created, isEmpty);
  });

  test("ensureDisplayablePath goes through the selected backend", () async {
    final harness = _Harness(rustOcr: true, isAndroid: true, isIOS: false);

    expect(
      await harness.service.ensureDisplayablePath("/tmp/photo.heic"),
      "rust:/tmp/photo.heic",
    );
  });
}
