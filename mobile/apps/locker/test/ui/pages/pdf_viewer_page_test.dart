import "dart:convert";
import "dart:io";

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:locker/ui/pages/pdf_viewer_page.dart";

void main() {
  const channel = MethodChannel("io.ente/pdf_renderer");
  final png = base64Decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=",
  );
  final calls = <MethodCall>[];
  var pageCount = 1;
  var pageSize = const Size(595, 842);
  var failRender = false;
  var openedExternally = 0;

  setUp(() {
    calls.clear();
    pageCount = 1;
    pageSize = const Size(595, 842);
    failRender = false;
    openedExternally = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case "open":
              return {
                "id": 1,
                "widths": List.filled(pageCount, pageSize.width),
                "heights": List.filled(pageCount, pageSize.height),
              };
            case "render":
              if (failRender) {
                throw PlatformException(code: "invalid", message: "boom");
              }
              return png;
            default:
              return null;
          }
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpViewer(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ComponentTheme.lightTheme(app: ComponentApp.locker),
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: const [Locale("en")],
        home: PdfViewerPage(
          localFile: File("/tmp/sample.pdf"),
          fileName: "sample.pdf",
          onOpenExternally: (_) async => openedExternally++,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> doubleTapAt(WidgetTester tester, Offset position) async {
    await tester.tapAt(position);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(position);
    await tester.pumpAndSettle();
  }

  testWidgets("a PDF with no pages shows the error state", (tester) async {
    pageCount = 0;
    await pumpViewer(tester);
    expect(find.text("Error opening item"), findsOneWidget);
    expect(calls.map((call) => call.method), ["open", "close"]);
  });

  testWidgets("a page that fails to render offers the external app", (
    tester,
  ) async {
    failRender = true;
    pageSize = const Size(842, 595);
    await pumpViewer(tester);

    expect(find.text("Error opening item"), findsOneWidget);
    await tester.tap(find.text("Open in another app"));
    await tester.pump(const Duration(milliseconds: 400));
    expect(openedExternally, 1);
  });

  testWidgets("double tap zooms around the tap and zooming out keeps place", (
    tester,
  ) async {
    pageCount = 6;
    await pumpViewer(tester);
    final viewer = find.byType(InteractiveViewer);
    final controller = tester
        .widget<InteractiveViewer>(viewer)
        .transformationController!;

    await tester.drag(viewer, const Offset(0, -2000));
    await tester.pumpAndSettle();
    final scrolled = controller.value.getTranslation().y;
    expect(scrolled, lessThan(-1500));

    final center = tester.getCenter(viewer);
    await doubleTapAt(tester, center);
    expect(controller.value.getMaxScaleOnAxis(), closeTo(2.5, 0.001));
    final focus = controller.toScene(center);

    await doubleTapAt(tester, center);
    expect(controller.value.getMaxScaleOnAxis(), closeTo(1, 0.001));
    expect(controller.toScene(center).dy, closeTo(focus.dy, 0.5));
    expect(controller.value.getTranslation().y, closeTo(scrolled, 0.5));
  });

  testWidgets("closes the document when the viewer is disposed", (
    tester,
  ) async {
    await pumpViewer(tester);
    calls.clear();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(calls.map((call) => call.method), ["close"]);
  });
}
