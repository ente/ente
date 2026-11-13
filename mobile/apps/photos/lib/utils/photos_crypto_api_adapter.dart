import "dart:typed_data";

import "package:ente_crypto/ente_crypto.dart" as ente_crypto;
import "package:ente_crypto_api/ente_crypto_api.dart";
import "package:flutter_sodium/flutter_sodium.dart";

// Reuses Photos' flutter_sodium for the lock screen instead of loading a second
// libsodium implementation. Methods unused by the lock screen throw.
class PhotosCryptoApiAdapter implements CryptoApi {
  const PhotosCryptoApiAdapter();

  @override
  Future<void> init() async {}

  @override
  Uint8List cryptoPwHash(
    Uint8List password,
    Uint8List salt,
    int memLimit,
    int opsLimit,
  ) => ente_crypto.cryptoPwHash({
    "password": password,
    "salt": salt,
    "memLimit": memLimit,
    "opsLimit": opsLimit,
  });

  @override
  Uint8List getSaltToDeriveKey() => ente_crypto.CryptoUtil.getSaltToDeriveKey();

  @override
  int get pwhashMemLimitInteractive => Sodium.cryptoPwhashMemlimitInteractive;

  @override
  int get pwhashMemLimitSensitive => Sodium.cryptoPwhashMemlimitSensitive;

  @override
  int get pwhashOpsLimitInteractive => Sodium.cryptoPwhashOpslimitInteractive;

  @override
  int get pwhashOpsLimitSensitive => Sodium.cryptoPwhashOpslimitSensitive;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    "PhotosCryptoApiAdapter implements only the lock-screen crypto subset; "
    "${invocation.memberName} is not available.",
  );
}
