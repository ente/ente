import 'package:ente_auth/core/configuration.dart';
import 'package:ente_configuration/base_configuration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('secure storage cleanup does not include offline auth key', () {
    final secureStorageKeys = Configuration.instance.secureStorageKeys;

    expect(
      secureStorageKeys,
      containsAll(BaseConfiguration.accountSecureStorageKeys),
    );
    expect(secureStorageKeys, contains(Configuration.authSecretKeyKey));
    expect(
      secureStorageKeys,
      isNot(contains(Configuration.offlineAuthSecretKey)),
    );
  });
}
