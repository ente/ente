import 'dart:convert';
import 'dart:ui' as ui;

import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/store/code_store.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

Future<String> generateQRImageBase64(String data) async {
  const size = 250.0;
  const padding = 20.0;

  final qrCode = QrCode.fromData(
    data: data,
    errorCorrectLevel: QrErrorCorrectLevel.L,
  );

  final qrPainter = QrPainter.withQr(
    qr: qrCode,
    gapless: true,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: Colors.black,
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: Colors.black,
    ),
  );

  const totalSize = size + padding * 2;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const paintBounds = Size(size, size);

  canvas.translate(padding, padding);

  qrPainter.paint(canvas, paintBounds);

  final picture = recorder.endRecording();
  final img = await picture.toImage(totalSize.toInt(), totalSize.toInt());
  final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
  final pngBytes = byteData!.buffer.asUint8List();

  return base64Encode(pngBytes);
}

Future<String> generateOTPEntryHtml(Code code) async {
  // Capitalize algorithm for Google Authenticator compatibility in QR codes
  final qrData = code.rawData
      .replaceAll('algorithm=Algorithm.', 'algorithm=')
      .replaceAll('algorithm=sha1', 'algorithm=SHA1')
      .replaceAll('algorithm=sha256', 'algorithm=SHA256')
      .replaceAll('algorithm=sha512', 'algorithm=SHA512');
  final qrBase64 = await generateQRImageBase64(qrData);
  String notes = code.display.note;
  if (notes.isNotEmpty) {
    notes = '<p class="group">Note: <b>$notes</b></p>';
  }
  return '''
    <table class="otp-entry">
      <tr>
        <td>
          <p><b>${code.issuer}</b></p>
          <p><b>${code.account}</b></p>
          <p class="group">Type: <b>${code.type.name}</b></p>
          <p>Algorithm: <b>${code.algorithm.name}</b></p>
          <p>Digits: <b>${code.digits}</b></p>
          <p>Secret: <b>${code.secret}</b></p>
          $notes
        </td>
        <td class="otp-qr">
          <img src="data:image/png;base64,$qrBase64" alt="QR Code">
        </td>
      </tr>
    </table>
    <br/>
    <hr class="red-separator" />
    <br/>
  ''';
}

Future<String> generateHtml(BuildContext context) async {
  DateTime now = DateTime.now().toUtc();
  String formattedDate = DateFormat('d MMMM, yyyy').format(now);
  final allCodes = await CodeStore.instance.getAllCodes();
  final List<String> enteries = [];

  for (final code in allCodes) {
    if (code.hasError) continue;
    final entry = await generateOTPEntryHtml(code);
    enteries.add(entry);
  }

  return '''
  <!DOCTYPE html>
  <html>
  <meta content="text/html; charset=utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, minimum-scale=1" />
  <style>
  body {
    background-color: #f0f1f3;
    font-family: "Helvetica Neue", "Segoe UI", Helvetica, sans-serif;
    font-size: 16px;
    line-height: 27px;
    margin: 0;
    color: #444;
  }

  pre {
    background: #f4f4f4f4;
    padding: 2px;
  }

  table {
    width: 100%;
  }

  table td {
    border-color: #ddd;
    padding: 5px;
  }

  .wrap {
    background-color: #fff;
    padding: 30px;
    max-width: 600px;
    margin: 0 auto;
    border-radius: 5px;
  }

  .button {
    background: #0055d4;
    border-radius: 3px;
    text-decoration: none !important;
    color: #fff !important;
    font-weight: bold;
    padding: 10px 30px;
    display: inline-block;
  }

  .button:hover {
    background: #111;
  }

  .footer {
    text-align: center;
    font-size: 12px;
    color: #888;
  }

  .footer a {
    color: #888;
    margin-right: 5px;
  }

  .gutter {
    padding: 30px;
  }

  img {
    max-width: 100%;
    height: auto;
  }

  a {
    color: #0055d4;
  }

  a:hover {
    color: #111;
  }

  @media screen and (max-width: 700px) {
    .otp-entry {
      display: block;
    }

    .otp-entry td {
      display: block;
      width: 100%;
    }

    .otp-qr img {
      margin-top: 10px;
    }
  }

  .footer-icons {
    padding: 4px !important;
    width: 24px !important;
  }

  .otp-entry {
    width: 100%;
    table-layout: fixed;
    border-collapse: collapse;
  }

  .otp-entry td {
    padding: 20px;
    margin: 0px;
    vertical-align: middle;
  }

  .otp-entry td:first-child {
    width: 70%;
    word-wrap: break-word;
    overflow-wrap: break-word;
  }

  .otp-qr img {
    max-width: 200px;
    height: auto;
    display: block;
    margin: 0 auto;
  }

  .otp-entry td.otp-qr {
    width: 30%;
    text-align: center;
    vertical-align: middle;
  }

  .otp-entry p {
    margin: 2px 0;
  }

  .otp-entry p.group {
    margin-top: 15px;
  }

  hr.red-separator {
    border: none;
    height: 1px;
    background-color: rgb(173, 0, 255);
  }
</style>
  </head>
  <body>
    <h1 style="text-align: center;">Ente Auth</h1>
    <h4 style="text-align: center; margin-bottom: 5px;">OTP Data Export</h4>
    <p style="text-align: center; margin-top: 0px;">$formattedDate</p>
    <div class="gutter" style="padding: 4px">&nbsp;</div>
    <div class="wrap" style=" background-color: rgb(255, 255, 255); padding: 2px
            30px 30px 30px; max-width: 700px; margin: 0 auto; border-radius: 5px;
            font-size: 16px; ">
      <main>
        <p>
          ${enteries.join('')}
        </p>
      </main>
    </div>
    <br />  
  
  <div class="footer" style="text-align: center; font-size: 12px; color:
    rgb(136, 136, 136)">
    <div>
      <a href="https://ente.com" target="_blank"><img src="https://email-assets.ente.com/ente-green.png" style="width: 100px;
        padding: 24px" title="Ente" alt="Ente" /></a>
    </div>
    <div>
      <a href="https://fosstodon.org/@ente" target="_blank"><img src="https://email-assets.ente.com/mastodon-icon.png"
          class="footer-icons" style="width: 24px; padding: 4px" title="Mastodon" alt="Mastodon" /></a>
      <a href="https://twitter.com/enteio" target="_blank"><img src="https://email-assets.ente.com/twitter-icon.png"
          class="footer-icons" style="width: 24px; padding: 4px" title="Twitter" alt="Twitter" /></a>
      <a href="https://ente.com/discord" target="_blank"><img src="https://email-assets.ente.com/discord-icon.png"
          class="footer-icons" style="width: 24px; padding: 4px" title="Discord" alt="Discord" /></a>
      <a href="https://github.com/ente" target="_blank"><img src="https://email-assets.ente.com/github-icon.png"
          class="footer-icons" style="width: 24px; padding: 4px" title="GitHub" alt="GitHub" /></a>
    </div>
    <p>
      Ente Technologies, Inc.
      <br /> 1111B S Governors Ave 6032 Dover, DE 19904
    </p>
    <br />
  </div>
  </body>
  
  </html>
  ''';
}
