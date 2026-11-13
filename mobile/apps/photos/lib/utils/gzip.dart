import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:computer/computer.dart";
import "package:ente_crypto/ente_crypto.dart";

class ChaChaEncryptionResult {
  final String encData;
  final String header;

  ChaChaEncryptionResult({required this.encData, required this.header});
}

Uint8List gunzipBytes(Uint8List compressedData, {int? maxOutputBytes}) {
  final output = _GzipOutputSink(maxOutputBytes);
  final decoder = gzip.decoder.startChunkedConversion(output);
  decoder.add(compressedData);
  decoder.close();
  return output.bytes.takeBytes();
}

class _GzipOutputSink implements Sink<List<int>> {
  final int? maxOutputBytes;
  final bytes = BytesBuilder(copy: false);

  _GzipOutputSink(this.maxOutputBytes);

  @override
  void add(List<int> data) {
    if (maxOutputBytes != null &&
        bytes.length + data.length > maxOutputBytes!) {
      throw const FormatException("Decompressed data exceeds the allowed size");
    }
    bytes.add(data);
  }

  @override
  void close() {}
}

Uint8List _gzipUInt8List(Uint8List data) {
  final codec = GZipCodec();
  final compressedData = codec.encode(data);
  return Uint8List.fromList(compressedData);
}

Future<Map<String, dynamic>> decryptAndUnzipJson(
  Uint8List key, {
  required String encryptedData,
  required String header,
  int? maxOutputBytes,
}) async {
  final Computer computer = Computer.shared();
  final response = await computer
      .compute<Map<String, dynamic>, Map<String, dynamic>>(
        _decryptAndUnzipJsonSync,
        param: {
          "key": key,
          "encryptedData": encryptedData,
          "header": header,
          "maxOutputBytes": maxOutputBytes,
        },
        taskName: "decryptAndUnzipJson",
      );
  return response;
}

Map<String, dynamic> decryptAndUnzipJsonSync(
  Uint8List key, {
  required String encryptedData,
  required String header,
  int? maxOutputBytes,
}) {
  final decryptedData = chachaDecryptData({
    "source": CryptoUtil.base642bin(encryptedData),
    "key": key,
    "header": CryptoUtil.base642bin(header),
  });
  final decompressedData = gunzipBytes(
    decryptedData,
    maxOutputBytes: maxOutputBytes,
  );
  final json = utf8.decode(decompressedData);
  return jsonDecode(json);
}

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
    maxOutputBytes: args["maxOutputBytes"],
  );
}
