import 'dart:typed_data';

class EncryptionResult {
  final Uint8List? encryptedData;
  final Uint8List? key;
  final Uint8List? header;
  final Uint8List? nonce;

  EncryptionResult({this.encryptedData, this.key, this.header, this.nonce});
}

class FileEncryptResult {
  // Key using which the file is encrypted
  final Uint8List key;
  // Header used for decrypting the file. This is stored in DB. We need both key and header to decrypt the file.
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
