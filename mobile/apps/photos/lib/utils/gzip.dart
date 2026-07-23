import "dart:convert";
import "dart:io";

import "package:computer/computer.dart";
import "package:ente_crypto/ente_crypto.dart";
import "package:flutter/foundation.dart";

class ChaChaEncryptionResult {
  final String encData;
  final String header;

  ChaChaEncryptionResult({required this.encData, required this.header});
}

Uint8List _unGzipUInt8List(Uint8List compressedData) {
  final codec = GZipCodec();
  final List<int> decompressedList = codec.decode(compressedData);
  return Uint8List.fromList(decompressedList);
}

// gzipUInt8List
Uint8List _gzipUInt8List(Uint8List data) {
  final codec = GZipCodec();
  final compressedData = codec.encode(data);
  return Uint8List.fromList(compressedData);
}

Future<Map<String, dynamic>> decryptAndUnzipJson(
  Uint8List key, {
  required String encryptedData,
  required String header,
}) async {
  final Computer computer = Computer.shared();
  final response = await computer
      .compute<Map<String, dynamic>, Map<String, dynamic>>(
        _decryptAndUnzipJsonSync,
        param: {"key": key, "encryptedData": encryptedData, "header": header},
        taskName: "decryptAndUnzipJson",
      );
  return response;
}

Map<String, dynamic> decryptAndUnzipJsonSync(
  Uint8List key, {
  required String encryptedData,
  required String header,
}) {
  final decryptedData = chachaDecryptData({
    "source": CryptoUtil.base642bin(encryptedData),
    "key": key,
    "header": CryptoUtil.base642bin(header),
  });
  final decompressedData = _unGzipUInt8List(decryptedData);
  final json = utf8.decode(decompressedData);
  return jsonDecode(json);
}

// zipJsonAndEncryptSync performs all operations synchronously, on a single isolate.
ChaChaEncryptionResult gzipAndEncryptJsonSync(
  Map<String, dynamic> jsonData,
  Uint8List key,
) {
  final json = utf8.encode(jsonEncode(jsonData));
  final compressedJson = _gzipUInt8List(Uint8List.fromList(json));
  final encryptedData = chachaEncryptData({
    "source": compressedJson,
    "key": key,
  });
  return ChaChaEncryptionResult(
    encData: CryptoUtil.bin2base64(encryptedData.encryptedData!),
    header: CryptoUtil.bin2base64(encryptedData.header!),
  );
}

Future<ChaChaEncryptionResult> gzipAndEncryptJson(
  Map<String, dynamic> jsonData,
  Uint8List key,
) async {
  final Computer computer = Computer.shared();
  final response = await computer
      .compute<Map<String, dynamic>, ChaChaEncryptionResult>(
        _gzipAndEncryptJsonSync,
        param: {"jsonData": jsonData, "key": key},
        taskName: "gzipAndEncryptJson",
      );
  return response;
}

ChaChaEncryptionResult _gzipAndEncryptJsonSync(Map<String, dynamic> args) {
  return gzipAndEncryptJsonSync(args["jsonData"], args["key"]);
}

Map<String, dynamic> _decryptAndUnzipJsonSync(Map<String, dynamic> args) {
  return decryptAndUnzipJsonSync(
    args["key"],
    encryptedData: args["encryptedData"],
    header: args["header"],
  );
}
