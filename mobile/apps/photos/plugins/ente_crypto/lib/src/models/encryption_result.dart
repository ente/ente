import 'dart:typed_data';

class EncryptionResult {
  final Uint8List? encryptedData;
  final Uint8List? key;
  final Uint8List? header;
  final Uint8List? nonce;

  EncryptionResult({this.encryptedData, this.key, this.header, this.nonce});
}

class FileEncryptResult {
  final Uint8List key;
  // Store this in the database; decryption requires both the header and key.
  final Uint8List header;
  final String? fileMd5;
  final List<String>? partMd5s;
  final int? partSize;

  FileEncryptResult({
    required this.key,
    required this.header,
    this.fileMd5,
    this.partMd5s,
    this.partSize,
  });
}
