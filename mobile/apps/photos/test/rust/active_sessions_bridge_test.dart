import 'dart:convert';
import 'dart:io';

import 'package:ente_frb/active_sessions.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photos/src/rust/frb_generated.dart';
import 'package:photos/src/rust/third_party/ente_frb_lib/active_sessions.dart';

import 'rust_test_helpers.dart';

void main() {
  final library = Platform.environment['ENTE_PHOTOS_FRB_LIBRARY'] ?? '';

  test(
    'lists and revokes active sessions through the generated Dart bindings',
    () async {
      await EntePhotosRust.init(externalLibrary: ExternalLibrary.open(library));
      final requests = <(String, String, String?)>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        requests.add((
          request.method,
          request.uri.path,
          request.uri.queryParameters['token'],
        ));
        request.response.headers.contentType = ContentType.json;
        if (request.method == 'GET') {
          request.response.write(
            jsonEncode({
              'sessions': [
                {
                  'token': 'th:current',
                  'isCurrent': true,
                  'creationTime': 1,
                  'lastUsedTime': 3,
                  'ip': '203.0.113.7',
                  'ua': 'ente-photos',
                  'prettyUA': 'Android, Ente Photos',
                },
                {
                  'token': 'th:other',
                  'isCurrent': false,
                  'creationTime': 2,
                  'lastUsedTime': 4,
                  'ip': '198.51.100.9',
                  'ua': 'ente-cli',
                  'prettyUA': 'Other, Other',
                },
              ],
            }),
          );
        }
        await request.response.close();
      });
      final session = openTestSession(server.port);
      addTearDown(session.dispose);

      final sessions = await listActiveSessions(session: session);
      expect(sessions, const [
        ActiveSession(
          id: 'th:current',
          isCurrent: true,
          createdAt: 1,
          lastUsedAt: 3,
          ip: '203.0.113.7',
          userAgent: 'ente-photos',
          prettyUserAgent: 'Android, Ente Photos',
        ),
        ActiveSession(
          id: 'th:other',
          isCurrent: false,
          createdAt: 2,
          lastUsedAt: 4,
          ip: '198.51.100.9',
          userAgent: 'ente-cli',
          prettyUserAgent: 'Other, Other',
        ),
      ]);

      await revokeActiveSession(session: session, id: 'th:other');
      expect(requests, [
        ('GET', '/users/sessions', null),
        ('DELETE', '/users/session', 'th:other'),
      ]);
    },
    skip: library.isEmpty
        ? 'Set ENTE_PHOTOS_FRB_LIBRARY to run against Rust'
        : false,
  );
}
