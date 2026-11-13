import 'package:ente_crypto_api/ente_crypto_api.dart';
import 'package:ente_crypto_dart/ente_crypto_dart.dart' as dart_impl;
import 'package:ente_crypto_dart_adapter/ente_crypto_dart_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('translateDartCryptoErrors', () {
    test('translates KeyDerivationError to the API error type', () async {
      final future = translateDartCryptoErrors<void>(
        () async => throw dart_impl.KeyDerivationError(),
      );

      await expectLater(future, throwsA(isA<KeyDerivationError>()));
    });

    test('translates LoginKeyDerivationError to the API error type', () async {
      final future = translateDartCryptoErrors<void>(
        () async => throw dart_impl.LoginKeyDerivationError(),
      );

      await expectLater(future, throwsA(isA<LoginKeyDerivationError>()));
    });

    test('preserves unrelated errors', () async {
      final error = StateError('test');
      final future = translateDartCryptoErrors<void>(() async => throw error);

      await expectLater(future, throwsA(same(error)));
    });
  });
}
