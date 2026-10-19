import "package:flutter/services.dart";

class PdfPasswordRequiredException implements Exception {
  const PdfPasswordRequiredException();
}

class PdfPasswordIncorrectException implements Exception {
  const PdfPasswordIncorrectException();
}

class PdfPasswordUnsupportedException implements Exception {
  const PdfPasswordUnsupportedException();
}

class PdfException implements Exception {
  const PdfException(this.message);

  final String message;

  @override
  String toString() => "PdfException: $message";
}

class EntePdfDocument {
  EntePdfDocument._(this._id, this.pageSizes);

  final int _id;
  final List<Size> pageSizes;

  int get pageCount => pageSizes.length;

  Future<Uint8List> render(
    int page, {
    required int width,
    required int height,
  }) async {
    final bytes = await EntePdfRenderer._invoke<Uint8List>("render", {
      "id": _id,
      "page": page,
      "width": width,
      "height": height,
    });
    if (bytes == null) {
      throw PdfException("Page $page rendered nothing");
    }
    return bytes;
  }

  Future<void> close() => EntePdfRenderer._invoke<void>("close", {"id": _id});
}

class EntePdfRenderer {
  static const _channel = MethodChannel("io.ente/pdf_renderer");

  static Future<EntePdfDocument> open(String path, {String? password}) async {
    final reply = await _invoke<Map<Object?, Object?>>("open", {
      "path": path,
      "password": password,
    });
    final widths = (reply!["widths"]! as List).cast<double>();
    final heights = (reply["heights"]! as List).cast<double>();
    return EntePdfDocument._(reply["id"]! as int, [
      for (var i = 0; i < widths.length; i++) Size(widths[i], heights[i]),
    ]);
  }

  static Future<T?> _invoke<T>(String method, Map<String, Object?> args) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      switch (e.code) {
        case "password_required":
          throw const PdfPasswordRequiredException();
        case "password_incorrect":
          throw const PdfPasswordIncorrectException();
        case "password_unsupported":
          throw const PdfPasswordUnsupportedException();
        default:
          throw PdfException(e.message ?? e.code);
      }
    }
  }
}
