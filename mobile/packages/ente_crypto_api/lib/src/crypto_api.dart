import 'dart:io';
import 'dart:typed_data';

import 'package:ente_crypto_api/src/models/crypto_key_pair.dart';
import 'package:ente_crypto_api/src/models/derived_key_result.dart';
import 'package:ente_crypto_api/src/models/encryption_result.dart';

abstract class CryptoApi {
  Future<void> init();

  Uint8List strToBin(String str);
  Uint8List base642bin(String b64);
  String bin2base64(Uint8List bin, {bool urlSafe = false});
  String bin2hex(Uint8List bin);
  Uint8List hex2bin(String hex);

  EncryptionResult encryptSync(Uint8List source, Uint8List key);
  Future<Uint8List> decrypt(Uint8List cipher, Uint8List key, Uint8List nonce);
  Uint8List decryptSync(Uint8List cipher, Uint8List key, Uint8List nonce);

  Future<EncryptionResult> encryptData(Uint8List source, Uint8List key);
  Future<Uint8List> decryptData(
    Uint8List source,
    Uint8List key,
    Uint8List header,
  );

  Future<EncryptionResult> encryptFile(
    String sourceFilePath,
    String destinationFilePath, {
    Uint8List? key,
  });

  Future<FileEncryptResult> encryptFileWithMd5(
    String sourceFilePath,
    String destinationFilePath, {
    Uint8List? key,
    int? multiPartChunkSizeInBytes,
  });

  Future<void> decryptFile(
    String sourceFilePath,
    String destinationFilePath,
    Uint8List header,
    Uint8List key,
  );

  Uint8List generateKey();
  CryptoKeyPair generateKeyPair();

  Uint8List openSealSync(
    Uint8List input,
    Uint8List publicKey,
    Uint8List secretKey,
  );

  Uint8List sealSync(Uint8List input, Uint8List publicKey);

  Future<DerivedKeyResult> deriveSensitiveKey(
    Uint8List password,
    Uint8List salt,
  );

  Future<DerivedKeyResult> deriveInteractiveKey(
    Uint8List password,
    Uint8List salt,
  );

  Future<Uint8List> deriveKey(
    Uint8List password,
    Uint8List salt,
    int memLimit,
    int opsLimit,
  );

  Future<Uint8List> deriveLoginKey(Uint8List key);

  Uint8List getSaltToDeriveKey();
  Uint8List cryptoPwHash(
    Uint8List password,
    Uint8List salt,
    int memLimit,
    int opsLimit,
  );

  // Expose the Argon2 limits so higher layers can tune mem/ops values.
  int get pwhashMemLimitInteractive;
  int get pwhashMemLimitSensitive;
  int get pwhashOpsLimitInteractive;
  int get pwhashOpsLimitSensitive;

  Future<Uint8List> getHash(File source);
}

class _CryptoApiRegistry {
  CryptoApi? _impl;

  static final _CryptoApiRegistry instance = _CryptoApiRegistry._();

  _CryptoApiRegistry._();

  void register(CryptoApi impl) => _impl = impl;

  CryptoApi get implementation {
    final impl = _impl;
    if (impl == null) {
      throw StateError(
        'CryptoApi implementation not registered. Call registerCryptoApi() '
        'before using CryptoUtil.',
      );
    }
    return impl;
  }

  bool get isRegistered => _impl != null;
}

void registerCryptoApi(CryptoApi impl) {
  _CryptoApiRegistry.instance.register(impl);
}

bool get isCryptoApiRegistered => _CryptoApiRegistry.instance.isRegistered;

class CryptoUtil {
  CryptoUtil._();

  static CryptoApi get _impl => _CryptoApiRegistry.instance.implementation;

  static Future<void> init() => _impl.init();

  static Uint8List strToBin(String str) => _impl.strToBin(str);
  static Uint8List base642bin(String b64) => _impl.base642bin(b64);
  static String bin2base64(Uint8List bin, {bool urlSafe = false}) =>
      _impl.bin2base64(bin, urlSafe: urlSafe);
  static String bin2hex(Uint8List bin) => _impl.bin2hex(bin);
  static Uint8List hex2bin(String hex) => _impl.hex2bin(hex);

  static EncryptionResult encryptSync(Uint8List source, Uint8List key) =>
      _impl.encryptSync(source, key);

  static Future<Uint8List> decrypt(
    Uint8List cipher,
    Uint8List key,
    Uint8List nonce,
  ) => _impl.decrypt(cipher, key, nonce);

  static Uint8List decryptSync(
    Uint8List cipher,
    Uint8List key,
    Uint8List nonce,
  ) => _impl.decryptSync(cipher, key, nonce);

  static Future<EncryptionResult> encryptData(
    Uint8List source,
    Uint8List key,
  ) => _impl.encryptData(source, key);

  static Future<Uint8List> decryptData(
    Uint8List source,
    Uint8List key,
    Uint8List header,
  ) => _impl.decryptData(source, key, header);

  static Future<EncryptionResult> encryptFile(
    String sourceFilePath,
    String destinationFilePath, {
    Uint8List? key,
  }) => _impl.encryptFile(sourceFilePath, destinationFilePath, key: key);

  static Future<FileEncryptResult> encryptFileWithMd5(
    String sourceFilePath,
    String destinationFilePath, {
    Uint8List? key,
    int? multiPartChunkSizeInBytes,
  }) => _impl.encryptFileWithMd5(
    sourceFilePath,
    destinationFilePath,
    key: key,
    multiPartChunkSizeInBytes: multiPartChunkSizeInBytes,
  );

  static Future<void> decryptFile(
    String sourceFilePath,
    String destinationFilePath,
    Uint8List header,
    Uint8List key,
  ) => _impl.decryptFile(sourceFilePath, destinationFilePath, header, key);

  static Uint8List generateKey() => _impl.generateKey();
  static CryptoKeyPair generateKeyPair() => _impl.generateKeyPair();

  static Uint8List openSealSync(
    Uint8List input,
    Uint8List publicKey,
    Uint8List secretKey,
  ) => _impl.openSealSync(input, publicKey, secretKey);

  static Uint8List sealSync(Uint8List input, Uint8List publicKey) =>
      _impl.sealSync(input, publicKey);

  static Future<DerivedKeyResult> deriveSensitiveKey(
    Uint8List password,
    Uint8List salt,
  ) => _impl.deriveSensitiveKey(password, salt);

  static Future<DerivedKeyResult> deriveInteractiveKey(
    Uint8List password,
    Uint8List salt,
  ) => _impl.deriveInteractiveKey(password, salt);

  static Future<Uint8List> deriveKey(
    Uint8List password,
    Uint8List salt,
    int memLimit,
    int opsLimit,
  ) => _impl.deriveKey(password, salt, memLimit, opsLimit);

  static Future<Uint8List> deriveLoginKey(Uint8List key) =>
      _impl.deriveLoginKey(key);

  static Uint8List getSaltToDeriveKey() => _impl.getSaltToDeriveKey();

  static Uint8List cryptoPwHash(
    Uint8List password,
    Uint8List salt,
    int memLimit,
    int opsLimit,
  ) => _impl.cryptoPwHash(password, salt, memLimit, opsLimit);

  static int get pwhashMemLimitInteractive => _impl.pwhashMemLimitInteractive;
  static int get pwhashMemLimitSensitive => _impl.pwhashMemLimitSensitive;
  static int get pwhashOpsLimitInteractive => _impl.pwhashOpsLimitInteractive;
  static int get pwhashOpsLimitSensitive => _impl.pwhashOpsLimitSensitive;

  static Future<Uint8List> getHash(File source) => _impl.getHash(source);
}
