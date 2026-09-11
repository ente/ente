import 'dart:convert';

import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/ui/settings/data/import/import_flow.dart';
import 'package:ente_auth/ui/settings/data/import/two_fas_import.dart';
import 'package:flutter_test/flutter_test.dart';

const _secret = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
const _groups = {'group-1': 'Synthetic group'};

void main() {
  group('parse2FasServices', () {
    for (final fixture in <({String name, Map<String, dynamic> otp})>[
      (name: 'algorithm omitted', otp: {'digits': 6, 'period': 30}),
      (name: 'digits omitted', otp: {'algorithm': 'SHA1', 'period': 30}),
      (name: 'algorithm and digits omitted', otp: {'period': 30}),
      (
        name: 'algorithm null',
        otp: {'algorithm': null, 'digits': 6, 'period': 30},
      ),
      (
        name: 'digits null',
        otp: {'algorithm': 'SHA1', 'digits': null, 'period': 30},
      ),
      (
        name: 'algorithm and digits null',
        otp: {'algorithm': null, 'digits': null, 'period': 30},
      ),
      (name: 'all defaults omitted', otp: {}),
      (
        name: 'period null',
        otp: {'algorithm': 'SHA1', 'digits': 6, 'period': null},
      ),
    ]) {
      test('uses TOTP defaults with ${fixture.name}', () {
        final entry = _entry(fixture.otp);
        final before = jsonEncode(entry);
        final codes = parse2FasServices([entry]);

        expect(codes, hasLength(1));
        _expectCode(codes.single);
        expect(jsonEncode(entry), before);
      });
    }

    for (final fixture in [
      ('SHA1', Algorithm.sha1),
      ('SHA256', Algorithm.sha256),
      ('SHA512', Algorithm.sha512),
      ('sHa256', Algorithm.sha256),
    ]) {
      test('preserves explicit ${fixture.$1}, digits and period', () {
        final codes = parse2FasServices([
          _entry({'algorithm': fixture.$1, 'digits': 8, 'period': 60}),
        ]);
        _expectCode(codes.single, algorithm: fixture.$2, digits: 8, period: 60);
      });
    }

    test('recognizes lowercase TOTP', () {
      _expectCode(
        parse2FasServices([
          _entry({'tokenType': 'totp'}),
        ]).single,
      );
    });

    test('retains name fallback and empty account', () {
      final entry = _entry({'issuer': null, 'account': null}, name: 'Fallback');
      _expectCode(
        parse2FasServices([entry]).single,
        issuer: 'Fallback',
        account: '',
      );
    });

    test('retains name fallback for an empty issuer', () {
      final entry = _entry({'issuer': ''}, name: 'Fallback');
      _expectCode(parse2FasServices([entry]).single, issuer: 'Fallback');
    });

    test('uses native secret sanitization', () {
      final entry = _entry({}, secret: ' gezdgnbv gy3tqojqgezdgnbvgy3tqojq ');
      _expectCode(parse2FasServices([entry]).single);
    });

    test('retains known group tags through serialization', () {
      final entry = _entry({}, groupId: 'group-1');
      final code = parse2FasServices([entry], groupIdToName: _groups).single;
      _expectCode(code, tags: ['Synthetic group']);
    });

    test('ignores an unknown group', () {
      final entry = _entry({}, groupId: 'unknown');
      _expectCode(parse2FasServices([entry], groupIdToName: _groups).single);
    });

    for (final fixture in [
      ('HOTP', Type.hotp, 6, 42),
      ('STEAM', Type.steam, 5, 0),
    ]) {
      test('preserves explicit ${fixture.$1} settings', () {
        final entry = _entry({
          'tokenType': fixture.$1,
          'algorithm': 'SHA1',
          'digits': fixture.$3,
          'period': 30,
          'counter': 42,
        });
        _expectCode(
          parse2FasServices([entry]).single,
          type: fixture.$2,
          digits: fixture.$3,
          counter: fixture.$4,
        );
      });
      for (final missingField in ['algorithm', 'digits']) {
        test('keeps ${fixture.$1} missing $missingField behavior', () {
          final settings = <String, dynamic>{
            'tokenType': fixture.$1,
            'algorithm': 'SHA1',
            'digits': fixture.$3,
          }..remove(missingField);
          _expectFailure(_entry(settings));
        });
      }
    }

    for (final counter in <int?>[null, 0]) {
      test('keeps HOTP counter ${counter ?? 'omitted'} as zero', () {
        final entry = _entry({
          'tokenType': 'HOTP',
          'algorithm': 'SHA1',
          'digits': 6,
          'counter': ?counter,
        });
        _expectCode(parse2FasServices([entry]).single, type: Type.hotp);
      });
    }

    test('retains a wrapped error for missing token type', () {
      _expectFailure(
        _entry({'tokenType': null, 'algorithm': 'SHA1', 'digits': 6}),
      );
    });

    for (final algorithm in <Object>[
      'SHA224',
      'SHA384',
      'not-an-algorithm',
      '',
      ' SHA1 ',
      'Algorithm.sha256',
      7,
      <String, Object>{},
      <Object>[],
    ]) {
      for (final digits in <int?>[null, 6]) {
        test(
          'rejects TOTP algorithm ${jsonEncode(algorithm)} with digits $digits',
          () {
            _expectFailure(
              _entry({'algorithm': algorithm, 'digits': digits}),
              message: 'Unsupported 2FAS TOTP algorithm',
            );
          },
        );
      }
    }

    test('keeps invalid digits rejected', () {
      _expectFailure(_entry({'digits': 11}), message: 'Invalid OTP digits: 11');
    });

    test('keeps negative HOTP counters rejected', () {
      _expectFailure(
        _entry({
          'tokenType': 'HOTP',
          'algorithm': 'SHA1',
          'digits': 6,
          'counter': -1,
        }),
        message: 'Invalid HOTP counter: -1',
      );
    });

    test('preserves input order', () {
      final codes = parse2FasServices([
        _entry({}, groupId: 'group-1'),
        _entry({'algorithm': 'SHA256', 'digits': 8, 'period': 60}),
      ], groupIdToName: _groups);
      expect(codes, hasLength(2));
      _expectCode(codes.first, tags: ['Synthetic group']);
      _expectCode(
        codes.last,
        algorithm: Algorithm.sha256,
        digits: 8,
        period: 60,
      );
    });

    test(
      'fails eagerly at the malformed entry without returning a partial list',
      () {
        final bad = _entry({'digits': 11});
        var visited = 0;
        Iterable<dynamic> entries() sync* {
          visited++;
          yield _entry({});
          visited++;
          yield bad;
          visited++;
          yield _entry({});
        }

        expect(
          () => parse2FasServices(entries()),
          throwsA(
            isA<ImportEntryParseException>().having(
              (error) => error.entry,
              'entry',
              same(bad),
            ),
          ),
        );
        expect(visited, 2);
      },
    );

    test('parses decrypted synthetic services through the same mapper', () {
      final services =
          jsonDecode(
                decrypt2FasVault({
                  'servicesEncrypted': _encryptedServices,
                }, password: 'synthetic-test-only'),
              )
              as List;
      final codes = parse2FasServices(services, groupIdToName: _groups);
      expect(codes, hasLength(2));
      _expectCode(codes.first, tags: ['Synthetic group']);
      _expectCode(
        codes.last,
        algorithm: Algorithm.sha256,
        digits: 8,
        period: 60,
      );
    });
  });
}

Map<String, dynamic> _entry(
  Map<String, dynamic> otp, {
  String name = 'Example',
  String secret = _secret,
  String? groupId,
}) =>
    jsonDecode(
          jsonEncode({
            'name': name,
            'secret': secret,
            'groupId': ?groupId,
            'otp': {
              'tokenType': 'TOTP',
              'issuer': 'Example',
              'account': 'synthetic@example.invalid',
              ...otp,
            },
          }),
        )
        as Map<String, dynamic>;

void _expectCode(
  Code code, {
  Type type = Type.totp,
  Algorithm algorithm = Algorithm.sha1,
  int digits = 6,
  int period = 30,
  int counter = 0,
  String issuer = 'Example',
  String account = 'synthetic@example.invalid',
  List<String> tags = const [],
}) {
  expect(code.type, type);
  expect(code.algorithm, algorithm);
  expect(code.digits, digits);
  expect(code.period, period);
  expect(code.counter, counter);
  expect(code.issuer, issuer);
  expect(code.account, account);
  expect(code.secret, _secret);
  expect(code.display.tags, tags);
  _roundTrip(code);
}

Code _roundTrip(Code code) {
  final restored = Code.fromOTPAuthUrl(
    jsonDecode(code.toOTPAuthUrlFormat()) as String,
  );
  expect(restored.type, code.type);
  expect(restored.algorithm, code.algorithm);
  expect(restored.digits, code.digits);
  expect(restored.period, code.period);
  expect(restored.counter, code.counter);
  expect(restored.issuer, code.issuer);
  expect(restored.account, code.account);
  expect(restored.secret, code.secret);
  expect(restored.display.toJson(), code.display.toJson());
  return restored;
}

void _expectFailure(Map<String, dynamic> entry, {String? message}) {
  ImportEntryParseException? caught;
  try {
    parse2FasServices([entry]);
  } on ImportEntryParseException catch (error) {
    caught = error;
  }
  expect(caught, isNotNull);
  expect(caught!.entry, same(entry));
  if (message != null) {
    expect(caught.error, isA<FormatException>());
    expect((caught.error as FormatException).message, message);
  }
  expect(caught.toString(), isNot(contains(_secret)));
  expect(caught.toString(), isNot(contains('synthetic@example.invalid')));
}

// Fixed synthetic plaintext/password/salt/nonce, generated independently with
// PBKDF2-HMAC-SHA256 (10,000 iterations, 32-byte key) and AES-256-GCM.
const _encryptedServices =
    '9uatiJpqe6rX1neqRCXxklo6EXykan6XH/TAKJmHh8tlb2VhS4QmNkmUUcYQiAy+Yle2zosctjK0'
    '/SRwGOV3M6z+dsfO8/irJL6VrTm5aZeqvCQKrdk5xR/LwyHn83x9kzFwExsN1XMAs7ESigqYPfwJ'
    '6EOI2mEdW5BQ8BaNQse9dhKCYwdrKE8qIEabTdAnOHzF2lj46YCjuL0kSc7C7eaaiVIWEW9qw5Tt'
    'WnVXX6X5NpGEURa3TZtVh3Kj4IXVfEeUDqcIkddVsQTMkqndgceWflLsJ+IIlq/MiSS5GBUCqciO'
    'J2c+uXsxixuz47jIO63ye6yYQ6tKsACG2JOBl5T/+vW408YHx5IC2mkg6fu4BrFzelE1KXs27lIv'
    'VXHXYtrwxWvZrVLjJ0a0y02gK4ytdyVKKecHYVLbPEqP8PQ7UG7zF2RC95p26GDqiVxxPzkqPAkX'
    'uUQxkChFDBtJlkM1COXgFEZ1niuqlK/cm5lRW5YFW7E=:AAECAwQFBgcICQoLDA0ODxAREhMUFRY'
    'XGBkaGxwdHh8=:AAECAwQFBgcICQoL';
