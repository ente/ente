import 'dart:convert';
import 'dart:typed_data';

class JpegInfo {
  const JpegInfo({
    required this.width,
    required this.height,
    required this.components,
  });

  final int width;
  final int height;
  final int components;

  String get pdfColorSpace => switch (components) {
    1 => '/DeviceGray',
    4 => '/DeviceCMYK',
    _ => '/DeviceRGB',
  };

  static JpegInfo parse(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      throw const FormatException('not a JPEG stream');
    }
    var offset = 2;
    while (offset + 3 < bytes.length) {
      if (bytes[offset] != 0xFF) {
        offset++;
        continue;
      }
      final marker = bytes[offset + 1];
      if (marker == 0xD8 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        offset += 2;
        continue;
      }
      if (marker == 0xD9 || marker == 0xDA) break;
      if (offset + 3 >= bytes.length) break;
      final length = (bytes[offset + 2] << 8) | bytes[offset + 3];
      final isFrameHeader =
          marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 &&
          marker != 0xC8 &&
          marker != 0xCC;
      if (isFrameHeader) {
        if (offset + 9 >= bytes.length) break;
        return JpegInfo(
          height: (bytes[offset + 5] << 8) | bytes[offset + 6],
          width: (bytes[offset + 7] << 8) | bytes[offset + 8],
          components: bytes[offset + 9],
        );
      }
      offset += 2 + length;
    }
    throw const FormatException('no JPEG frame header found');
  }
}

class PdfPageSpec {
  const PdfPageSpec({
    required this.jpeg,
    required this.widthMm,
    required this.heightMm,
  });

  final Uint8List jpeg;
  final double widthMm;
  final double heightMm;
}

({double widthMm, double heightMm}) constrainToMaxFormat(
  double widthMm,
  double heightMm,
) {
  const maxDim = 297.0;
  const minDim = 215.9;
  final scale = [
    maxDim / (widthMm > heightMm ? widthMm : heightMm),
    minDim / (widthMm < heightMm ? widthMm : heightMm),
    1.0,
  ].reduce((a, b) => a < b ? a : b);
  return (widthMm: widthMm * scale, heightMm: heightMm * scale);
}

const double pointsPerMm = 72.0 / 25.4;

class PdfWriter {
  const PdfWriter({required this.creator});

  final String creator;

  Uint8List build(List<PdfPageSpec> pages, {DateTime? creationDate}) {
    final out = BytesBuilder(copy: false);
    final offsets = <int>[];

    void raw(List<int> bytes) => out.add(bytes);
    void text(String value) => raw(latin1.encode(value));

    int pageObj(int index) => 4 + index * 3;
    int contentObj(int index) => pageObj(index) + 1;
    int imageObj(int index) => pageObj(index) + 2;
    final objectCount = 3 + pages.length * 3;

    void startObject(int number) {
      while (offsets.length < number) {
        offsets.add(0);
      }
      offsets[number - 1] = out.length;
      text('$number 0 obj\n');
    }

    text('%PDF-1.4\n');
    raw([0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);

    startObject(1);
    text('<< /Type /Catalog /Pages 2 0 R >>\nendobj\n');

    startObject(2);
    final kids = List.generate(
      pages.length,
      (i) => '${pageObj(i)} 0 R',
    ).join(' ');
    text('<< /Type /Pages /Kids [$kids] /Count ${pages.length} >>\nendobj\n');

    startObject(3);
    final stamp = _pdfDate(creationDate ?? DateTime.now());
    text(
      '<< /Producer (${_escape(creator)}) /Creator (${_escape(creator)}) '
      '/CreationDate ($stamp) >>\nendobj\n',
    );

    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final info = JpegInfo.parse(page.jpeg);
      final widthPt = page.widthMm * pointsPerMm;
      final heightPt = page.heightMm * pointsPerMm;

      startObject(pageObj(i));
      text(
        '<< /Type /Page /Parent 2 0 R '
        '/MediaBox [0 0 ${_num(widthPt)} ${_num(heightPt)}] '
        '/Resources << /XObject << /Im0 ${imageObj(i)} 0 R >> >> '
        '/Contents ${contentObj(i)} 0 R >>\nendobj\n',
      );

      final content =
          'q\n${_num(widthPt)} 0 0 ${_num(heightPt)} 0 0 cm\n/Im0 Do\nQ\n';
      final contentBytes = latin1.encode(content);
      startObject(contentObj(i));
      text('<< /Length ${contentBytes.length} >>\nstream\n');
      raw(contentBytes);
      text('endstream\nendobj\n');

      startObject(imageObj(i));
      text(
        '<< /Type /XObject /Subtype /Image /Width ${info.width} '
        '/Height ${info.height} /ColorSpace ${info.pdfColorSpace} '
        '/BitsPerComponent 8 /Filter /DCTDecode '
        '/Length ${page.jpeg.length} >>\nstream\n',
      );
      raw(page.jpeg);
      text('\nendstream\nendobj\n');
    }

    final xrefOffset = out.length;
    text('xref\n0 ${objectCount + 1}\n');
    text('0000000000 65535 f \n');
    for (var i = 0; i < objectCount; i++) {
      text('${offsets[i].toString().padLeft(10, '0')} 00000 n \n');
    }
    text(
      'trailer\n<< /Size ${objectCount + 1} /Root 1 0 R /Info 3 0 R >>\n'
      'startxref\n$xrefOffset\n%%EOF\n',
    );

    return out.takeBytes();
  }

  static String _num(double value) {
    final rounded = (value * 1000).roundToDouble() / 1000;
    if (rounded == rounded.roundToDouble()) return rounded.toStringAsFixed(0);
    return rounded.toString();
  }

  static String _escape(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('(', r'\(')
      .replaceAll(')', r'\)');

  static String _pdfDate(DateTime when) {
    final utc = when.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return 'D:${utc.year}${two(utc.month)}${two(utc.day)}'
        '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z';
  }
}
