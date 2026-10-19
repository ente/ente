import "package:ente_pdf_renderer/ente_pdf_renderer.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel("io.ente/pdf_renderer");
  final calls = <MethodCall>[];

  void respond(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) {
          calls.add(call);
          return handler(call);
        });
  }

  void fail(String code, {String? message}) {
    respond(
      (call) async => throw PlatformException(code: code, message: message),
    );
  }

  setUp(calls.clear);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test("open maps page sizes and renders through the document id", () async {
    respond((call) async {
      switch (call.method) {
        case "open":
          return {
            "id": 7,
            "widths": [595.0, 842.0],
            "heights": [842.0, 595.0],
          };
        case "render":
          return Uint8List.fromList([1, 2, 3]);
        default:
          return null;
      }
    });

    final document = await EntePdfRenderer.open("/tmp/a.pdf", password: "x");
    expect(document.pageCount, 2);
    expect(document.pageSizes[1], const Size(842, 595));
    expect(calls.single.arguments, {"path": "/tmp/a.pdf", "password": "x"});

    final bytes = await document.render(2, width: 100, height: 70);
    expect(bytes, [1, 2, 3]);
    expect(calls.last.arguments, {
      "id": 7,
      "page": 2,
      "width": 100,
      "height": 70,
    });

    await document.close();
    expect(calls.last.method, "close");
  });

  test("platform error codes become typed exceptions", () async {
    fail("password_required");
    await expectLater(
      EntePdfRenderer.open("/tmp/a.pdf"),
      throwsA(isA<PdfPasswordRequiredException>()),
    );

    fail("password_incorrect");
    await expectLater(
      EntePdfRenderer.open("/tmp/a.pdf", password: "nope"),
      throwsA(isA<PdfPasswordIncorrectException>()),
    );

    fail("password_unsupported");
    await expectLater(
      EntePdfRenderer.open("/tmp/a.pdf"),
      throwsA(isA<PdfPasswordUnsupportedException>()),
    );

    fail("invalid", message: "Unable to load");
    await expectLater(
      EntePdfRenderer.open("/tmp/a.pdf"),
      throwsA(
        isA<PdfException>().having(
          (e) => e.message,
          "message",
          "Unable to load",
        ),
      ),
    );
  });
}
