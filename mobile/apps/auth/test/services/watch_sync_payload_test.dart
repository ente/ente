import 'dart:convert';
import 'dart:io';

import 'package:ente_auth/models/code.dart';
import 'package:ente_auth/models/code_display.dart';
import 'package:ente_auth/models/watch_sync_payload.dart';
import 'package:ente_auth/services/preference_service.dart';
import 'package:ente_auth/utils/totp_util.dart';
import 'package:flutter_test/flutter_test.dart';

const _secret = 'JBSWY3DPEHPK3PXP';
const _timestamp = 1775736000;

void main() {
  test('pinned TOTP is included with generatedID and isFavorite', () {
    final payload = buildWatchPayload(
      [
        _code(id: 42, pinned: true),
      ],
      syncAll: false,
      deletedIds: const <String>{},
      timestamp: _timestamp,
    );

    final json = payload.toJson();
    expect(json['version'], 1);
    expect(json['version'], isA<int>());
    expect(json['syncType'], 'DELTA');
    expect(json['timestamp'], _timestamp);
    expect(json['timestamp'], isA<int>());

    final token = _tokens(payload).single;
    expect(token['id'], '42');
    expect(token['issuer'], 'GitHub');
    expect(token['account'], 'octocat@github.com');
    expect(token['secret'], _secret);
    expect(token['algorithm'], 'SHA1');
    expect(token['digits'], 6);
    expect(token['digits'], isA<int>());
    expect(token['period'], 30);
    expect(token['period'], isA<int>());
    expect(token['isFavorite'], isTrue);
    expect(token['sortOrder'], 0);
    expect(token['sortOrder'], isA<int>());
  });

  test('unpinned #watch tag is included and isFavorite is false', () {
    final payload = buildWatchPayload(
      [
        _code(id: 1, tags: const ['#watch']),
        _code(id: 2, issuer: 'Work', tags: const ['  #watch  ']),
        _code(id: 3, issuer: 'Other', tags: const ['#Watch']),
      ],
      syncAll: false,
      deletedIds: const <String>{},
      timestamp: _timestamp,
    );

    final tokens = _tokens(payload);
    expect(tokens.map((token) => token['id']), ['1', '2']);
    expect(tokens.every((token) => token['isFavorite'] == false), isTrue);
  });

  test('unpinned code without the tag is excluded when syncAll is false', () {
    final payload = buildWatchPayload(
      [
        _code(id: 4),
      ],
      syncAll: false,
      deletedIds: const <String>{},
      timestamp: _timestamp,
    );

    expect(_tokens(payload), isEmpty);
    expect(payload.deletedIds, isEmpty);
  });

  test('syncAll includes an unpinned TOTP', () {
    final payload = buildWatchPayload(
      [
        _code(id: 5),
      ],
      syncAll: true,
      deletedIds: const <String>{},
      timestamp: _timestamp,
    );

    final token = _tokens(payload).single;
    expect(token['id'], '5');
    expect(token['isFavorite'], isFalse);
  });

  test('trashed code is omitted and a passed id stays in deletedIds', () {
    final payload = buildWatchPayload(
      [
        _code(id: 9, pinned: true, trashed: true),
        _code(id: 10, pinned: true),
      ],
      syncAll: false,
      deletedIds: const {'9', 'missing'},
      timestamp: _timestamp,
    );

    expect(_tokens(payload).map((token) => token['id']), ['10']);
    expect(payload.deletedIds, containsAll(<String>['9', 'missing']));
    expect(payload.deletedIds, hasLength(2));
    expect(payload.toJson()['deletedIds'], isNot(contains('10')));
  });

  test('steam type and steam issuer are excluded', () {
    final payload = buildWatchPayload(
      [
        _code(id: 11, type: Type.steam, issuer: 'Valve', pinned: true),
        _code(id: 12, issuer: 'Steam', pinned: true),
        _code(id: 13, issuer: 'sTeAm', pinned: true),
        _code(id: 14, issuer: 'GitHub', pinned: true),
      ],
      syncAll: true,
      deletedIds: const <String>{},
      timestamp: _timestamp,
    );

    expect(_tokens(payload).map((token) => token['id']), ['14']);
  });

  test('HOTP is excluded', () {
    final payload = buildWatchPayload(
      [
        _code(id: 15, type: Type.hotp, pinned: true, tags: const ['#watch']),
        _code(id: 16, pinned: true),
      ],
      syncAll: true,
      deletedIds: const <String>{},
      timestamp: _timestamp,
    );

    expect(_tokens(payload).map((token) => token['id']), ['16']);
  });

  test('null generatedID is omitted and the secret is not an id', () {
    const raw = 'otpauth://totp/GitHub:octocat?secret=$_secret';
    final payload = buildWatchPayload(
      [
        _code(id: null, pinned: true, secret: _secret, rawData: raw),
      ],
      syncAll: false,
      deletedIds: const {'404'},
      timestamp: _timestamp,
    );

    final json = payload.toJson();
    expect(json['tokens'], isEmpty);
    expect(json['deletedIds'], ['404']);
    expect(json.toString().contains(_secret), isFalse);
    expect(json.toString().contains(raw), isFalse);
  });

  test('hasError excludes the code', () {
    final payload = buildWatchPayload(
      [
        _code(id: 17, pinned: true, err: StateError('parse')),
        _code(id: 18, pinned: true),
      ],
      syncAll: true,
      deletedIds: const <String>{},
      timestamp: _timestamp,
    );

    expect(_tokens(payload).map((token) => token['id']), ['18']);
    expect(payload.deletedIds, isEmpty);
  });

  test('manual sortOrder follows position and does not force pinned first', () {
    final payload = buildWatchPayload(
      [
        _code(id: 1, pinned: true, position: 10, issuer: 'Pinned'),
        _code(id: 2, tags: const ['#watch'], position: 0, issuer: 'First'),
        _code(id: 3, tags: const ['#watch'], position: 5, issuer: 'Middle'),
        _code(id: 4, position: 1, issuer: 'Skipped'),
      ],
      syncAll: false,
      deletedIds: const <String>{},
      sortKey: CodeSortKey.manual,
      timestamp: _timestamp,
    );

    final tokens = _tokens(payload);
    expect(tokens.map((token) => token['id']), ['2', '3', '1']);
    expect(tokens.map((token) => token['sortOrder']), [0, 1, 2]);
    expect(tokens[0]['isFavorite'], isFalse);
    expect(tokens[2]['isFavorite'], isTrue);
  });

  test('issuerName puts pinned codes first, then issuer order', () {
    final payload = buildWatchPayload(
      [
        _code(id: 1, issuer: 'Zoom', tags: const ['#watch']),
        _code(id: 2, issuer: 'microsoft', pinned: true),
        _code(id: 3, issuer: 'alpha', tags: const ['#watch']),
        _code(id: 4, issuer: 'Dropbox', pinned: true),
        _code(id: 5, issuer: 'Ignored'),
      ],
      syncAll: false,
      deletedIds: const <String>{},
      sortKey: CodeSortKey.issuerName,
      timestamp: _timestamp,
    );

    final tokens = _tokens(payload);
    expect(tokens.map((token) => token['issuer']), [
      'Dropbox',
      'microsoft',
      'alpha',
      'Zoom',
    ]);
    expect(tokens.map((token) => token['sortOrder']), [0, 1, 2, 3]);
    expect(tokens[0]['isFavorite'], isTrue);
    expect(tokens[1]['isFavorite'], isTrue);
    expect(tokens[2]['isFavorite'], isFalse);
    expect(tokens[3]['isFavorite'], isFalse);
  });

  test('secret with spaces and lowercase matches getSanitizedSecret', () {
    const rawSecret = '  jbsw y3dp ehpk 3pxp  ';
    final payload = buildWatchPayload(
      [
        _code(id: 19, pinned: true, secret: rawSecret),
      ],
      syncAll: false,
      deletedIds: const <String>{},
      timestamp: _timestamp,
    );

    expect(_tokens(payload).single['secret'], getSanitizedSecret(rawSecret));
    expect(_tokens(payload).single['secret'], 'JBSWY3DPEHPK3PXP');
  });

  test('envelope is version 1 DELTA', () {
    final payload = buildWatchPayload(
      const <Code>[],
      syncAll: false,
      deletedIds: const <String>{},
      timestamp: _timestamp,
    );
    final json = payload.toJson();

    expect(json['version'], 1);
    expect(json['syncType'], 'DELTA');
    expect(json['tokens'], isEmpty);
    expect(json['deletedIds'], isEmpty);
  });

  test('newestFirst uses createdAt descending and leaves nulls last', () {
    final payload = buildWatchPayload(
      [
        _code(id: 1, tags: const ['#watch'], createdAt: 100),
        _code(id: 2, pinned: true, createdAt: 50),
        _code(id: 4, tags: const ['#watch'], createdAt: 100),
        _code(id: 3, tags: const ['#watch']),
      ],
      syncAll: false,
      deletedIds: const <String>{},
      sortKey: CodeSortKey.newestFirst,
      timestamp: _timestamp,
    );

    expect(_tokens(payload).map((token) => token['id']), ['2', '4', '1', '3']);
  });

  test('digits, period, and SHA512 pass through', () {
    final payload = buildWatchPayload(
      [
        _code(
          id: 21,
          pinned: true,
          digits: 8,
          period: 45,
          algorithm: Algorithm.sha512,
        ),
      ],
      syncAll: false,
      deletedIds: const <String>{},
      timestamp: _timestamp,
    );

    final token = _tokens(payload).single;
    expect(token['digits'], 8);
    expect(token['period'], 45);
    expect(token['algorithm'], 'SHA512');
  });

  test('lowercase padded secret is uppercased and keeps padding', () {
    const rawSecret = 'jbswy3dpee======';
    final payload = buildWatchPayload(
      [
        _code(id: 22, pinned: true, secret: rawSecret),
      ],
      syncAll: false,
      deletedIds: const <String>{},
      timestamp: _timestamp,
    );

    expect(_tokens(payload).single['secret'], 'JBSWY3DPEE======');
    expect(getSanitizedSecret('  jbsw y3dp ee======  '), 'JBSWY3DPEE======');
  });

  test('SHA256 algorithm name is uppercased', () {
    final payload = buildWatchPayload(
      [
        _code(id: 20, pinned: true, algorithm: Algorithm.sha256),
      ],
      syncAll: false,
      deletedIds: const <String>{},
      timestamp: _timestamp,
    );

    expect(_tokens(payload).single['algorithm'], 'SHA256');
  });

  test('shared fixture matches the watch contract keys', () {
    final fixture = jsonDecode(
      File('test/fixtures/watch_sync_contract_v1.json').readAsStringSync(),
    );
    final payload = buildWatchPayload(
      [
        _code(id: 42, pinned: true),
        _code(
          id: 7,
          issuer: 'Example',
          account: 'ada@example.com',
          algorithm: Algorithm.sha256,
          digits: 8,
          tags: const ['#watch'],
        ),
        _code(id: 9, pinned: true, trashed: true),
      ],
      syncAll: false,
      deletedIds: const {'9'},
      sortKey: CodeSortKey.issuerName,
      timestamp: _timestamp,
    );

    final json = _canonicalize(payload.toJson());
    expect(
      (json as Map<String, Object?>).keys.toSet(),
      {'version', 'timestamp', 'syncType', 'tokens', 'deletedIds'},
    );
    final tokens = json['tokens']! as List<Object?>;
    expect(tokens, isNotEmpty);
    for (final token in tokens) {
      expect((token! as Map<String, Object?>).keys.toSet(), {
        'id',
        'issuer',
        'account',
        'secret',
        'algorithm',
        'digits',
        'period',
        'isFavorite',
        'sortOrder',
      });
    }
    expect(json, _canonicalize(fixture));
  });

  test('an id in tokens is removed from deletedIds', () {
    final payload = buildWatchPayload(
      [
        _code(id: 7, pinned: true),
      ],
      syncAll: false,
      deletedIds: const {'7', '8'},
      timestamp: _timestamp,
    );

    expect(_tokens(payload).single['id'], '7');
    expect(payload.deletedIds, ['8']);
    final deleted = payload.toJson()['deletedIds']! as List<Object?>;
    expect(deleted.contains('7'), isFalse);
  });
}

Code _code({
  required int? id,
  String issuer = 'GitHub',
  String account = 'octocat@github.com',
  String secret = _secret,
  Algorithm algorithm = Algorithm.sha1,
  Type type = Type.totp,
  int digits = Code.defaultDigits,
  int period = Code.defaultPeriod,
  bool pinned = false,
  bool trashed = false,
  List<String> tags = const [],
  int position = 0,
  int? createdAt,
  Object? err,
  String? rawData,
}) {
  final code = Code(
    account,
    issuer,
    digits,
    period,
    secret,
    algorithm,
    type,
    0,
    rawData ?? 'otpauth://${type.name}/$issuer:$account?secret=$secret',
    generatedID: id,
    display: CodeDisplay(
      pinned: pinned,
      trashed: trashed,
      tags: tags,
      position: position,
    ),
    err: err,
  );
  code.createdAt = createdAt;
  return code;
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        entry.key as String: _canonicalize(entry.value),
    };
  }
  if (value is List) {
    return <Object?>[for (final item in value) _canonicalize(item)];
  }
  return value;
}

List<Map<String, Object?>> _tokens(WatchSyncPayload payload) {
  final tokens = payload.toJson()['tokens']! as List<Object?>;
  return [
    for (final token in tokens) Map<String, Object?>.from(token! as Map),
  ];
}
