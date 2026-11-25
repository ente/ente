import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/network/endpoint_config.dart';
import 'package:photos/gateways/collections/models/public_url.dart';
import 'package:photos/services/pending_uploads_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final root = await Directory.systemTemp.createTemp('pending_uploads_');
    messenger.setMockMethodCallHandler(pathProvider, (_) async => root.path);
    addTearDown(() async {
      messenger.setMockMethodCallHandler(pathProvider, null);
      await root.delete(recursive: true);
    });
    SharedPreferences.setMockInitialValues({Configuration.userIDKey: 7});
    FlutterSecureStorage.setMockInitialValues({});
    await Configuration.instance.init(await SharedPreferences.getInstance());
  });

  test('link support follows whether the server sent the field', () {
    final old = PublicURL.fromMap({
      'url': 'link',
      'deviceLimit': 0,
      'validTill': 0,
    });
    expect(old.requireApproval, isFalse);
    expect(old.approvalSupported, isFalse);
    expect(old.toMap().containsKey('requireApproval'), isFalse);
    final current = PublicURL.fromMap({
      'url': 'link',
      'deviceLimit': 0,
      'requireApproval': false,
    });
    expect(current.approvalSupported, isTrue);
    expect(PublicURL.fromMap(current.toMap()).approvalSupported, isTrue);
  });

  test('album diff keeps live pending rows for this session only', () async {
    final prefs = await SharedPreferences.getInstance();
    final service = PendingUploadsService(Dio(), prefs);

    service.applyDiff(42, [
      {'id': 1, 'moderationStatus': 'PENDING'},
      {'id': 2, 'moderationStatus': 'PENDING'},
      {'id': 3, 'updationTime': 4},
    ], service.session);
    expect(service.count(42), 2);

    service.applyDiff(42, [
      {'id': 1, 'isDeleted': true},
      {'id': 2},
    ], service.session);
    expect(service.count(42), 0);

    service.applyDiff(42, [
      {'id': 5, 'moderationStatus': 'PENDING'},
    ], service.session);
    expect(PendingUploadsService(Dio(), prefs).count(42), 0);
  });

  test('rows are dropped when the server or account changes', () async {
    final prefs = await SharedPreferences.getInstance();
    final service = PendingUploadsService(Dio(), prefs);
    service.applyDiff(42, [
      {'id': 1, 'moderationStatus': 'PENDING'},
    ], service.session);
    expect(service.count(42), 1);

    await prefs.setString(EndpointConfig.preferencesKey, 'https://other.test');
    expect(service.count(42), 0);
  });

  test(
    'late responses are discarded after signing back into the same account',
    () async {
      final prefs = await SharedPreferences.getInstance();
      FlutterSecureStorage.setMockInitialValues({
        Configuration.keyKey: 'test-key',
      });
      await prefs.setString(Configuration.tokenKey, 'first-test-session');
      await Configuration.instance.init(prefs);
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            await prefs.setString(Configuration.tokenKey, 'next-test-session');
            await Configuration.instance.init(prefs);
            handler.resolve(
              Response(
                requestOptions: options,
                data: {
                  'diff': [
                    {'id': 1, 'updationTime': 1, 'moderationStatus': 'PENDING'},
                  ],
                  'hasMore': false,
                },
              ),
            );
          },
        ),
      );
      final service = PendingUploadsService(dio, prefs);
      final oldSession = service.session;

      await service.resync(42);
      expect(service.count(42), 0);

      service.applyDiff(42, [
        {'id': 2, 'moderationStatus': 'PENDING'},
      ], oldSession);
      expect(service.count(42), 0);
    },
  );

  test('first load pages from zero with its own cursor, once', () async {
    final requests = <Map<String, dynamic>>[];
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests.add(options.queryParameters);
          final since = options.queryParameters['sinceTime'] as int;
          handler.resolve(
            Response(
              requestOptions: options,
              data: since == 0
                  ? {
                      'diff': [
                        {
                          'id': 1,
                          'updationTime': 10,
                          'moderationStatus': 'PENDING',
                        },
                        {'id': 2, 'updationTime': 11},
                      ],
                      'hasMore': true,
                    }
                  : {
                      'diff': [
                        {
                          'id': 3,
                          'updationTime': 12,
                          'moderationStatus': 'PENDING',
                        },
                      ],
                      'hasMore': false,
                    },
            ),
          );
        },
      ),
    );
    final service = PendingUploadsService(
      dio,
      await SharedPreferences.getInstance(),
    );

    expect(await service.loadedCount(42), 2);
    expect(requests.map((query) => query['sinceTime']), [0, 11]);
    expect(requests.first['includePending'], isTrue);
    expect(await service.loadedCount(42), 2);
    expect(requests, hasLength(2));
  });

  test('review queue reverses choices and keeps both kinds', () {
    final queue = ReviewQueue();
    queue.choose(1, ReviewChoice.approve);
    queue.choose(2, ReviewChoice.reject);
    queue.choose(1, ReviewChoice.reject);
    expect((queue.approveCount, queue.rejectCount), (0, 2));
    final resumed = ReviewQueue.fromJson(queue.toJson());
    resumed.undo();
    expect((resumed.approveCount, resumed.rejectCount), (1, 1));
    resumed.retain([1]);
    expect((resumed.approveCount, resumed.rejectCount), (1, 0));
  });

  test('submit posts the ids and drops them from the store', () async {
    final calls = <Map>[];
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls.add(options.data as Map);
          handler.resolve(Response(requestOptions: options));
        },
      ),
    );
    final service = PendingUploadsService(
      dio,
      await SharedPreferences.getInstance(),
    );
    service.applyDiff(42, [
      {'id': 1, 'moderationStatus': 'PENDING'},
      {'id': 2, 'moderationStatus': 'PENDING'},
    ], service.session);
    await service.submit(42, 'approve', [1]);
    expect(calls.single, {
      'collectionID': 42,
      'fileIDs': [1],
    });
    expect(service.count(42), 1);
  });
}
