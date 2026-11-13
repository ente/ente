import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
// The fake implements the camera plugin's platform contract.
// ignore: depend_on_referenced_packages
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locker/services/scanner/document_scanner_service.dart';
import 'package:locker/src/rust/api/document_scanner_api.dart';
import 'package:locker/src/rust/frb_generated.dart';
import 'package:locker/ui/pages/scanner/scan_quad_overlay.dart';
import 'package:locker/ui/pages/scanner/scanner_capture_page.dart';
import 'package:locker/ui/pages/scanner/scanner_capture_widgets.dart';
import 'package:locker/ui/pages/scanner/scanner_review_page.dart';

void main() {
  late _Camera camera;
  late _ScannerSession scanner;
  late CameraPlatform originalCamera;
  late Directory root;
  late GlobalKey<NavigatorState> navigator;
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  const mobilePlatforms = TargetPlatformVariant({
    TargetPlatform.iOS,
    TargetPlatform.android,
  });

  setUp(() async {
    originalCamera = CameraPlatform.instance;
    camera = _Camera();
    CameraPlatform.instance = camera;
    navigator = GlobalKey<NavigatorState>();
    root = await Directory.systemTemp.createTemp('scanner_transition_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => root.path);
    scanner = _ScannerSession();
    scanner.image = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==',
    );
    camera.shot = XFile.fromData(scanner.image!, path: '${root.path}/shot.png');
    EnteLockerRust.initMock(api: _ScannerApi(scanner));
    await DocumentScannerService.instance.init();
  });

  tearDown(() async {
    await DocumentScannerService.instance.dispose();
    EnteLockerRust.dispose();
    CameraPlatform.instance = originalCamera;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, null);
    await root.delete(recursive: true);
  });

  Future<void> flushCamera(WidgetTester tester) async {
    // Platform messages complete outside the widget test's animation clock.
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump();
    }
  }

  Future<void> pumpUntil(WidgetTester tester, bool Function() ready) async {
    // Capture I/O and decoding run outside the animation clock.
    for (var attempt = 0; attempt < 50 && !ready(); attempt++) {
      await flushCamera(tester);
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        theme: ComponentTheme.lightTheme(app: ComponentApp.locker),
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en')],
        home: const Scaffold(body: Text('Home')),
      ),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.push(
      MaterialPageRoute<bool>(
        builder: (_) => ScannerCapturePage(onUploadFiles: (_) async => false),
      ),
    );
    await tester.pump();
    await flushCamera(tester);
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> finishClose(WidgetTester tester) async {
    await tester.pumpAndSettle();
    expect(find.byType(ScannerCapturePage), findsNothing);
    await flushCamera(tester);
  }

  testWidgets('preview opens before streaming; analysis waits for entry', (
    tester,
  ) async {
    await open(tester);
    expect(find.byType(CameraPreview), findsOneWidget);
    expect(camera.settings!.resolutionPreset, ResolutionPreset.max);
    expect(camera.starts, 0);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(camera.starts, 1);
    navigator.currentState!.pop();
    await finishClose(tester);
    expect(camera.disposals, 1);
  }, variant: mobilePlatforms);

  testWidgets('pop stops streaming while retaining the exit preview', (
    tester,
  ) async {
    await open(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(camera.starts, 1);
    navigator.currentState!.pop();
    await tester.pump();
    expect(camera.stops, 1);
    expect(camera.disposals, 0);
    expect(find.byType(CameraPreview), findsOneWidget);
    await finishClose(tester);
    expect(camera.disposals, 1);
  }, variant: mobilePlatforms);

  testWidgets('manual capture remains available while analysis awaits entry', (
    tester,
  ) async {
    await open(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(camera.starts, 0);
    await tester.tap(find.byType(ScannerShutterButton));
    await flushCamera(tester);
    expect(camera.pictures, 1);
    await tester.pump(const Duration(milliseconds: 500));
    await flushCamera(tester);
    navigator.currentState!.pop();
    await finishClose(tester);
  }, variant: mobilePlatforms);

  testWidgets('a Dart stream-start failure exposes retry and can recover', (
    tester,
  ) async {
    camera.failStream = true;
    await open(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await flushCamera(tester);
    expect(find.text('Retry'), findsOneWidget);
    expect(camera.disposals, 1);
    camera.failStream = false;
    await tester.tap(find.text('Retry'));
    await flushCamera(tester);
    expect(camera.starts, 1);
    expect(find.byType(CameraPreview), findsOneWidget);
    navigator.currentState!.pop();
    await finishClose(tester);
  }, variant: mobilePlatforms);

  testWidgets('review opens after stream-stop failure and camera resumes', (
    tester,
  ) async {
    camera.pictureDelay = const Duration(milliseconds: 200);
    await open(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await flushCamera(tester);
    await tester.tap(find.byType(ScannerShutterButton));
    await pumpUntil(
      tester,
      () => tester
          .widget<ScannerDoneButton>(find.byType(ScannerDoneButton))
          .visible,
    );
    expect(
      tester.widget<ScannerDoneButton>(find.byType(ScannerDoneButton)).visible,
      isTrue,
    );
    await tester.pump(const Duration(milliseconds: 500));
    camera.failStop = true;
    await tester.tap(find.byType(ScannerDoneButton));
    await pumpUntil(
      tester,
      () => find.byType(ScannerReviewPage).evaluate().isNotEmpty,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(camera.stops, 1);
    expect(camera.disposals, 1);
    expect(find.byType(ScannerReviewPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    camera.failStop = false;
    navigator.currentState!.pop();
    await tester.pump(const Duration(milliseconds: 500));
    await pumpUntil(tester, () => camera.starts == 2);
    expect(find.byType(CameraPreview), findsOneWidget);
    expect(camera.starts, 2);
    navigator.currentState!.pop();
    await finishClose(tester);
  }, variant: mobilePlatforms);

  testWidgets('Retry still works when stream-error cleanup fails', (
    tester,
  ) async {
    camera.failStream = true;
    camera.failDispose = true;
    await open(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await flushCamera(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Retry'), findsOneWidget);
    camera.failStream = false;
    camera.failDispose = false;
    await tester.tap(find.text('Retry'));
    await flushCamera(tester);
    expect(camera.starts, 1);
    navigator.currentState!.pop();
    await finishClose(tester);
  }, variant: mobilePlatforms);

  testWidgets('back swipe clears an already displayed detection quad', (
    tester,
  ) async {
    await open(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await flushCamera(tester);
    scanner.detection = Completer<RustQuad?>()
      ..complete(
        const RustQuad(
          topLeft: RustPoint(x: 10, y: 10),
          topRight: RustPoint(x: 246, y: 10),
          bottomRight: RustPoint(x: 246, y: 246),
          bottomLeft: RustPoint(x: 10, y: 246),
        ),
      );
    camera.frames!.add(
      CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.bgra8888, raw: 0),
        planes: [CameraImagePlane(bytes: Uint8List(16), bytesPerRow: 8)],
        height: 2,
        width: 2,
      ),
    );
    await flushCamera(tester);
    expect(
      tester.widget<ScanQuadOverlay>(find.byType(ScanQuadOverlay)).quad,
      isNotNull,
    );
    final gesture = await tester.startGesture(const Offset(1, 300));
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.widget<ScanQuadOverlay>(find.byType(ScanQuadOverlay)).quad,
      isNull,
    );
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 500));
    await flushCamera(tester);
    navigator.currentState!.pop();
    await finishClose(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('cancelled back swipe resumes only after settling open', (
    tester,
  ) async {
    await open(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await flushCamera(tester);
    final gesture = await tester.startGesture(const Offset(1, 300));
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(camera.stops, 1);
    expect(camera.disposals, 0);
    expect(camera.starts, 1);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
    expect(camera.starts, 1);
    await tester.pump(const Duration(milliseconds: 500));
    await flushCamera(tester);
    expect(camera.starts, 2);
    expect(camera.disposals, 0);
    navigator.currentState!.pop();
    await finishClose(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('closing during initialization never starts streaming', (
    tester,
  ) async {
    camera.initialization = Completer<void>();
    await open(tester);
    expect(camera.creations, 1);
    navigator.currentState!.pop();
    await tester.pump();
    camera.initialization!.complete();
    await flushCamera(tester);
    expect(camera.starts, 0);
    expect(camera.disposals, 1);
    await finishClose(tester);
  }, variant: mobilePlatforms);

  testWidgets('closing before orientation setup never initializes the camera', (
    tester,
  ) async {
    final orientation = Completer<void>();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations' &&
          (call.arguments as List).isNotEmpty) {
        await orientation.future;
      }
      return null;
    });
    try {
      await open(tester);
      expect(camera.creations, 0);
      navigator.currentState!.pop();
      await tester.pump();
      orientation.complete();
      await flushCamera(tester);
      expect(camera.creations, 0);
      await finishClose(tester);
    } finally {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    }
  }, variant: mobilePlatforms);

  testWidgets('route removal stops streaming and disposes the camera', (
    tester,
  ) async {
    await open(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await flushCamera(tester);
    final route = ModalRoute.of(
      tester.element(find.byType(ScannerCapturePage)),
    )!;
    navigator.currentState!.removeRoute(route);
    await tester.pumpAndSettle();
    await flushCamera(tester);
    expect(camera.stops, 1);
    expect(camera.disposals, 1);
    expect(find.byType(ScannerCapturePage), findsNothing);
  }, variant: mobilePlatforms);

  testWidgets('a late detection cannot update the departing scanner', (
    tester,
  ) async {
    await open(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await flushCamera(tester);
    scanner.detection = Completer<RustQuad?>();
    camera.frames!.add(
      CameraImageData(
        format: const CameraImageFormat(ImageFormatGroup.bgra8888, raw: 0),
        planes: [CameraImagePlane(bytes: Uint8List(16), bytesPerRow: 8)],
        height: 2,
        width: 2,
      ),
    );
    await tester.pump();
    expect(scanner.detections, 1);
    navigator.currentState!.pop();
    await tester.pump();
    scanner.detection!.complete(
      const RustQuad(
        topLeft: RustPoint(x: 10, y: 10),
        topRight: RustPoint(x: 246, y: 10),
        bottomRight: RustPoint(x: 246, y: 246),
        bottomLeft: RustPoint(x: 10, y: 246),
      ),
    );
    await tester.pump();
    expect(
      tester.widget<ScanQuadOverlay>(find.byType(ScanQuadOverlay)).quad,
      isNull,
    );
    expect(camera.starts, 1);
    expect(camera.stops, 1);
    await finishClose(tester);
  }, variant: mobilePlatforms);

  testWidgets(
    'route disposal handles stream-stop failure and releases camera',
    (tester) async {
      await open(tester);
      await tester.pump(const Duration(milliseconds: 500));
      await flushCamera(tester);
      camera.failStop = true;
      final route = ModalRoute.of(
        tester.element(find.byType(ScannerCapturePage)),
      )!;
      navigator.currentState!.removeRoute(route);
      await finishClose(tester);
      expect(camera.stops, 1);
      expect(camera.disposals, 1);
      expect(tester.takeException(), isNull);
    },
    variant: mobilePlatforms,
  );
}

class _Camera extends CameraPlatform {
  int starts = 0;
  int stops = 0;
  int disposals = 0;
  int creations = 0;
  int pictures = 0;
  Duration pictureDelay = Duration.zero;
  bool failStream = false;
  bool failStop = false;
  bool failDispose = false;
  MediaSettings? settings;
  Completer<void>? initialization;
  StreamController<CameraImageData>? frames;
  XFile? shot;

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    CameraDescription(
      name: 'back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 0,
    ),
  ];

  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings mediaSettings,
  ) async {
    settings = mediaSettings;
    return ++creations;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    await initialization?.future;
  }

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          1080,
          1920,
          ExposureMode.auto,
          true,
          FocusMode.auto,
          true,
        ),
      );

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      StreamController<CameraErrorEvent>().stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      Stream.value(
        const DeviceOrientationChangedEvent(DeviceOrientation.portraitUp),
      );

  @override
  Future<void> lockCaptureOrientation(
    int cameraId,
    DeviceOrientation orientation,
  ) async {}

  @override
  bool supportsImageStreaming() => true;

  @override
  Stream<CameraImageData> onStreamedFrameAvailable(
    int cameraId, {
    CameraImageStreamOptions? options,
  }) {
    if (failStream) throw CameraException('stream-start', 'Stream failed');
    frames = StreamController<CameraImageData>(
      onListen: () => starts++,
      onCancel: () {
        stops++;
        if (failStop) throw CameraException('stream-stop', 'Stop failed');
      },
    );
    return frames!.stream;
  }

  @override
  Widget buildPreview(int cameraId) => const SizedBox.expand();

  @override
  Future<XFile> takePicture(int cameraId) async {
    pictures++;
    if (pictureDelay != Duration.zero) {
      await Future<void>.delayed(pictureDelay);
    }
    return shot!;
  }

  @override
  Future<void> dispose(int cameraId) async {
    disposals++;
    if (failDispose) throw CameraException('dispose', 'Cleanup failed');
  }
}

class _ScannerApi implements EnteLockerRustApi {
  _ScannerApi(this.scanner);
  final _ScannerSession scanner;

  @override
  Future<ScannerSession> crateApiDocumentScannerApiScannerSessionCreate({
    required String assetsDir,
  }) async => scanner;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ScannerSession implements ScannerSession {
  Completer<RustQuad?>? detection;
  int detections = 0;
  Uint8List? image;

  @override
  Future<RustScanResult> processCapture({
    required List<int> imageBytes,
    int? maxPixels,
    RustCaptureRegion? region,
  }) async => RustScanResult(
    colorMode: RustColorMode.color,
    outputWidth: 1,
    outputHeight: 1,
    sourceWidth: 1,
    sourceHeight: 1,
    processedImage: image!,
  );

  @override
  Future<RustQuad?> liveDetectBgra({
    required List<int> bgra,
    required int rowStride,
    required int width,
    required int height,
    required int rotationDegrees,
  }) async {
    detections++;
    return await detection?.future;
  }

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
