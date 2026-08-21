import 'package:ente_components/ente_components.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('avatar identity seeds are stable and normalized', () {
    expect(
      avatarSeedForIdentity(' Alice@Example.com '),
      avatarSeedForIdentity('alice@example.com'),
    );
    expect(avatarSeedForIdentity('alice@example.com'), 2493822278);
  });
}
