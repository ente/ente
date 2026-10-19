import "dart:async";
import "dart:io";

import "package:flutter/widgets.dart";
import "package:logging/logging.dart";
import "package:photos/models/file/extensions/file_props.dart";
import "package:photos/models/file/file.dart";
import "package:photos/module/download/file.dart";
import "package:photos/services/machine_learning/ocr/ocr_backend.dart";
import "package:photos/services/machine_learning/ocr/ocr_models.dart";
import "package:photos/services/machine_learning/ocr/rust_ocr_backend.dart";
import "package:photos/services/machine_learning/ocr/vision_ocr_backend.dart";

enum OcrBackendKind { rust, vision }

class OcrService with WidgetsBindingObserver {
  OcrService({
    required bool isAndroid,
    required bool isIOS,
    OcrBackend Function()? createRustBackend,
    OcrBackend Function()? createVisionBackend,
  }) : _isAndroid = isAndroid,
       _isIOS = isIOS,
       _createRustBackend = createRustBackend ?? RustOcrBackend.new,
       _createVisionBackend = createVisionBackend ?? VisionOcrBackend.new;

  static final instance = OcrService(
    isAndroid: Platform.isAndroid,
    isIOS: Platform.isIOS,
  ).._observeAppLifecycle();

  static final _logger = Logger("OcrService");
  static const _modelUnloadDelay = Duration(seconds: 30);

  final bool _isAndroid;
  final bool _isIOS;
  final OcrBackend Function() _createRustBackend;
  final OcrBackend Function() _createVisionBackend;
  late final OcrBackendKind backendKind = _chooseBackendKind();
  late final OcrBackend _backend = _createBackend(backendKind);
  Future<void>? _modelPreload;
  Future<void>? _modelUnload;
  Timer? _modelUnloadTimer;
  int _viewerCount = 0;
  int _activeOperations = 0;
  bool _isBackgrounded = false;
  bool _preloadRequested = false;
  bool _unloadRequested = false;
  bool _modelsMayBeLoaded = false;

  void _observeAppLifecycle() {
    if (!_isAndroid) return;
    final binding = WidgetsBinding.instance;
    binding.addObserver(this);
    final state = binding.lifecycleState;
    if (state != null) didChangeAppLifecycleState(state);
  }

  void onViewerOpened() {
    if (!_isAndroid) return;
    _viewerCount++;
    _modelUnloadTimer?.cancel();
    _modelUnloadTimer = null;
    _unloadRequested = _isBackgrounded;
  }

  void onViewerClosed() {
    if (!_isAndroid) return;
    _viewerCount--;
    if (_viewerCount != 0) return;
    _preloadRequested = false;
    if (_isBackgrounded) {
      _requestModelUnload();
    } else {
      _modelUnloadTimer = Timer(_modelUnloadDelay, _requestModelUnload);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isAndroid) return;
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _isBackgrounded = true;
        _requestModelUnload();
      case AppLifecycleState.resumed:
        _isBackgrounded = false;
        if (_viewerCount > 0) {
          _unloadRequested = false;
          if (_preloadRequested) unawaited(preloadModels());
        }
      case AppLifecycleState.inactive:
        break;
    }
  }

  void _requestModelUnload() {
    _modelUnloadTimer?.cancel();
    _modelUnloadTimer = null;
    _unloadRequested = true;
    _unloadModelsIfIdle();
  }

  void _unloadModelsIfIdle() {
    if (!_unloadRequested ||
        !_modelsMayBeLoaded ||
        _activeOperations != 0 ||
        _modelUnload != null) {
      return;
    }
    _modelPreload = null;
    _modelsMayBeLoaded = false;
    _modelUnload = Future.sync(_backend.unloadModels)
        .catchError((Object error, StackTrace stackTrace) {
          _modelsMayBeLoaded = true;
          _logger.warning("Could not unload OCR models", error, stackTrace);
        })
        .whenComplete(() => _modelUnload = null);
  }

  Future<T> _withModels<T>(Future<T> Function() operation) async {
    if (!_isAndroid) return operation();
    _activeOperations++;
    try {
      await _modelUnload;
      _modelsMayBeLoaded = true;
      return await operation();
    } finally {
      _activeOperations--;
      _unloadModelsIfIdle();
    }
  }

  OcrBackendKind _chooseBackendKind() {
    final kind = _preferredBackendKind();
    _logger.info("Using the ${kind.name} OCR backend");
    return kind;
  }

  OcrBackendKind _preferredBackendKind() {
    if (_isAndroid) {
      return OcrBackendKind.rust;
    }
    if (_isIOS) {
      return OcrBackendKind.vision;
    }
    throw UnsupportedError("OCR is only supported on Android and iOS");
  }

  Future<void> preloadModels() {
    if (!_isAndroid) return Future.value();
    _preloadRequested = true;
    if (_isBackgrounded) return Future.value();
    final pending = _modelPreload;
    if (pending != null) return pending;
    late final Future<void> preload;
    preload = Future.sync(() => prepareModels()).then<void>((_) {}).catchError((
      Object error,
    ) {
      if (identical(_modelPreload, preload)) _modelPreload = null;
      _logger.warning("Could not preload OCR models: $error");
    });
    _modelPreload = preload;
    return preload;
  }

  Future<ModelPreparationStatus> prepareModels({
    Set<OcrModelComponent>? components,
  }) {
    return _withModels(
      () => _backend.prepareModels(
        components ?? OcrModelComponent.values.toSet(),
      ),
    );
  }

  Future<TextDetectionResult> detectText({
    required String imagePath,
    bool includeAllConfidenceScores = false,
  }) async {
    _ensureImageExists(imagePath);
    return _withModels(
      () => _backend.detectText(
        imagePath: imagePath,
        includeAllConfidenceScores: includeAllConfidenceScores,
      ),
    );
  }

  Future<TextRegionDetectionResult> detectTextRegions({
    required String imagePath,
  }) async {
    _ensureImageExists(imagePath);
    return _withModels(() => _backend.detectTextRegions(imagePath: imagePath));
  }

  Future<String> ensureDisplayablePath(String imagePath) {
    return _backend.ensureDisplayablePath(imagePath);
  }

  Future<File?> resolveImageFile(EnteFile file) async {
    final localFile = await getFile(file);
    if (localFile != null && await localFile.exists()) return localFile;
    if (file.localID == null ||
        file.isSharedMediaToAppSandbox ||
        file.isDeviceTrash) {
      return null;
    }
    try {
      final asset = await file.getAsset;
      if (asset == null || !await asset.exists) return null;
      final refreshedFile = await asset.file;
      return refreshedFile != null && await refreshedFile.exists()
          ? refreshedFile
          : null;
    } catch (error, stackTrace) {
      _logger.warning(
        "Could not refresh device image for OCR",
        error,
        stackTrace,
      );
      return null;
    }
  }

  OcrBackend _createBackend(OcrBackendKind kind) => switch (kind) {
    OcrBackendKind.rust => _createRustBackend(),
    OcrBackendKind.vision => _createVisionBackend(),
  };

  void _ensureImageExists(String imagePath) {
    if (!File(imagePath).existsSync()) {
      throw ArgumentError("Image file does not exist at path: $imagePath");
    }
  }
}
