import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photos/gateways/collections/models/public_url.dart';
import 'package:photos/services/pending_uploads_service.dart';

Dio _dioWith(void Function(RequestOptions options) onRequest, Object? data) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        onRequest(options);
        handler.resolve(Response(requestOptions: options, data: data));
      },
    ),
  );
  return dio;
}

void main() {
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

  test('only live pending rows count as pending', () {
    expect(isPendingRow({'moderationStatus': 'PENDING'}), isTrue);
    expect(
      isPendingRow({'moderationStatus': 'PENDING', 'isDeleted': true}),
      isFalse,
    );
    expect(isPendingRow({'moderationStatus': 'APPROVED'}), isFalse);
    expect(isPendingRow({}), isFalse);
  });

  test('every load reads pending rows from zero', () async {
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
    final service = PendingUploadsService(dio);

    expect(await service.load(42), isEmpty);
    expect(requests.map((query) => query['sinceTime']), [0, 11]);
    expect(requests.first['collectionID'], 42);
    expect(requests.first['includePending'], isTrue);

    await service.load(42);
    expect(requests.map((query) => query['sinceTime']), [0, 11, 0, 11]);
  });

  test('review queue reverses, removes and retains choices', () {
    final queue = ReviewQueue();
    queue.choose(1, ReviewChoice.approve);
    queue.choose(2, ReviewChoice.reject);
    queue.choose(1, ReviewChoice.reject);
    expect((queue.approveCount, queue.rejectCount), (0, 2));
    queue.undo();
    expect((queue.approveCount, queue.rejectCount), (1, 1));
    queue.choose(3, ReviewChoice.approve);
    queue.remove([3]);
    expect((queue.approveCount, queue.rejectCount), (1, 1));
    queue.retain([1]);
    expect((queue.approveCount, queue.rejectCount), (1, 0));
  });

  test('submit posts the album and file ids', () async {
    final calls = <(String, Object?)>[];
    final service = PendingUploadsService(
      _dioWith((options) => calls.add((options.path, options.data)), null),
    );

    await service.submit(42, 'reject', [1, 2]);

    expect(calls.single.$1, '/collections/pending-files/reject');
    expect(calls.single.$2, {
      'collectionID': 42,
      'fileIDs': [1, 2],
    });
  });
}
