import 'dart:typed_data';

class CryptoKeyPair {
  final Uint8List publicKey;
  final Uint8List secretKey;

  const CryptoKeyPair({required this.publicKey, required this.secretKey});
}
