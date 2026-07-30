import "dart:collection";
import "dart:io";

import "package:dio/dio.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/errors.dart";
import "package:photos/gateways/files/file_upload_gateway.dart";
import "package:photos/models/file/file.dart";
import "package:photos/module/upload/model/upload_url.dart";
import "package:photos/module/upload/service/upload_transport.dart";

void main() {
  late Directory tempDir;
  late File file;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp("upload_transport_test_");
    file = File("${tempDir.path}/payload")..writeAsBytesSync([1, 2, 3, 4]);
  });

  tearDownAll(() => tempDir.delete(recursive: true));

  test("requires MD5 before URL or object requests", () async {
    final fixture = _Fixture();

    await expectLater(
      fixture.transport.uploadSinglePart(file, 4, contentMd5: ""),
      throwsA(isA<StateError>()),
    );

    expect(fixture.gateway.uploadURLRequests, isEmpty);
    expect(fixture.dio.putPaths, isEmpty);
  });

  test("maps upload URL 402 and 426 responses and clears the queue", () async {
    for (final statusCode in [402, 426]) {
      final fixture = _Fixture();
      fixture.gateway.uploadURLFailures.add(_dioError(statusCode: statusCode));

      await expectLater(
        fixture.transport.uploadSinglePart(file, 4, contentMd5: "md5"),
        throwsA(
          statusCode == 402
              ? isA<NoActiveSubscriptionError>()
              : isA<StorageLimitExceededError>(),
        ),
      );

      expect(fixture.clearedErrors, hasLength(1));
    }
  });

  test("leaves other upload URL response failures unchanged", () async {
    final fixture = _Fixture();
    final error = _dioError(statusCode: 413);
    fixture.gateway.uploadURLFailures.add(error);

    await expectLater(
      fixture.transport.uploadSinglePart(file, 4, contentMd5: "md5"),
      throwsA(same(error)),
    );

    expect(fixture.clearedErrors, isEmpty);
    expect(fixture.dio.putPaths, isEmpty);
  });

  test("streams direct and proxy PUTs with their existing headers", () async {
    final fixture = _Fixture();
    fixture.gateway.uploadURLs.addAll([
      UploadURL("direct-url", "direct-key"),
      UploadURL("proxy-url", "proxy-key"),
    ]);

    expect(
      await fixture.transport.uploadSinglePart(
        file,
        4,
        contentMd5: "direct-md5",
      ),
      "direct-key",
    );
    fixture.useProxy = true;
    expect(
      await fixture.transport.uploadSinglePart(
        file,
        4,
        contentMd5: "proxy-md5",
      ),
      "proxy-key",
    );

    expect(fixture.dio.putPaths, [
      "direct-url",
      "$kUploadProxyEndpoint/file-upload",
    ]);
    expect(fixture.dio.payloads, [
      [1, 2, 3, 4],
      [1, 2, 3, 4],
    ]);
    expect(fixture.dio.headers[0], {
      Headers.contentLengthHeader: 4,
      "Content-MD5": "direct-md5",
    });
    expect(fixture.dio.headers[1], {
      Headers.contentLengthHeader: 4,
      "UPLOAD-URL": "proxy-url",
      "CONTENT-MD5": "proxy-md5",
    });
  });

  test("PUT retries four times with a fresh signed URL", () async {
    final fixture = _Fixture();
    fixture.gateway.uploadURLs.addAll([
      UploadURL("url-1", "key-1"),
      UploadURL("url-2", "key-2"),
      UploadURL("url-3", "key-3"),
      UploadURL("url-4", "key-4"),
    ]);
    fixture.dio.putFailures.addAll([_dioError(), _dioError(), _dioError()]);
    final objectKey = await fixture.transport.uploadSinglePart(
      file,
      4,
      contentMd5: "md5",
    );

    expect(objectKey, "key-4");
    expect(fixture.dio.putPaths, ["url-1", "url-2", "url-3", "url-4"]);
    expect(fixture.gateway.uploadURLRequests, hasLength(4));
    expect(fixture.dio.payloads, everyElement([1, 2, 3, 4]));
  });

  test("PUT stops after four failures", () async {
    final fixture = _Fixture();
    fixture.gateway.uploadURLs.addAll(
      List.generate(
        4,
        (index) => UploadURL("url-${index + 1}", "key-${index + 1}"),
      ),
    );
    final finalError = _dioError(statusCode: 500);
    fixture.dio.putFailures.addAll([
      _dioError(statusCode: 500),
      _dioError(statusCode: 500),
      _dioError(statusCode: 500),
      finalError,
    ]);
    await expectLater(
      fixture.transport.uploadSinglePart(file, 4, contentMd5: "md5"),
      throwsA(same(finalError)),
    );

    expect(fixture.dio.putPaths, hasLength(4));
    expect(fixture.gateway.uploadURLRequests, hasLength(4));
  });

  test("PUT retries response failures without clearing the queue", () async {
    for (final statusCode in [402, 413, 426]) {
      final fixture = _Fixture();
      fixture.gateway.uploadURLs.addAll([
        UploadURL("url-$statusCode-1", "key-$statusCode-1"),
        UploadURL("url-$statusCode-2", "key-$statusCode-2"),
      ]);
      fixture.dio.putFailures.add(_dioError(statusCode: statusCode));

      expect(
        await fixture.transport.uploadSinglePart(file, 4, contentMd5: "md5"),
        "key-$statusCode-2",
      );
      expect(fixture.gateway.uploadURLRequests, hasLength(2));
      expect(fixture.clearedErrors, isEmpty);
    }
  });

  test("maps a fatal upload URL failure during PUT retry", () async {
    for (final statusCode in [402, 426]) {
      final fixture = _Fixture();
      final retryURLFailure = _dioError(statusCode: statusCode);
      fixture.gateway.uploadURLs.add(UploadURL("initial", "initial-key"));
      fixture.dio
        ..putFailures.add(_dioError(statusCode: 500))
        ..onPutFailure = () {
          fixture.gateway.uploadURLFailures.add(retryURLFailure);
        };

      await expectLater(
        fixture.transport.uploadSinglePart(file, 4, contentMd5: "md5"),
        throwsA(
          statusCode == 402
              ? isA<NoActiveSubscriptionError>()
              : isA<StorageLimitExceededError>(),
        ),
      );

      expect(fixture.gateway.uploadURLRequests, hasLength(2));
      expect(fixture.clearedErrors, hasLength(1));
    }
  });

  test("PUT reports digest errors without retrying", () async {
    final fixture = _Fixture();
    fixture.gateway.uploadURLs.add(UploadURL("url", "key"));
    fixture.dio.putFailures.add(_dioError(statusCode: 400, data: "BadDigest"));
    final expectedMd5 = await computeMd5(file.path);

    await expectLater(
      fixture.transport.uploadSinglePart(file, 4, contentMd5: "sent"),
      throwsA(
        isA<BadMD5DigestError>().having(
          (error) => error.message,
          "message",
          contains("sent: sent, computed: $expectedMd5"),
        ),
      ),
    );

    expect(fixture.dio.putPaths, hasLength(1));
    expect(fixture.gateway.uploadURLRequests, hasLength(1));
  });

  test("PUT does not retry content-size transport failures", () async {
    final fixture = _Fixture();
    fixture.gateway.uploadURLs.add(UploadURL("url", "key"));
    final error = _dioError(message: "HttpException: Content size mismatch");
    fixture.dio.putFailures.add(error);

    await expectLater(
      fixture.transport.uploadSinglePart(file, 4, contentMd5: "md5"),
      throwsA(same(error)),
    );

    expect(fixture.dio.putPaths, hasLength(1));
    expect(fixture.gateway.uploadURLRequests, hasLength(1));
  });

  test("create sends commit data and applies the response", () async {
    final fixture = _Fixture();
    fixture.gateway.createResults.add({
      "id": 11,
      "updationTime": 12,
      "ownerID": 13,
    });
    final enteFile = EnteFile()..localID = "local";

    final result = await fixture.transport.createFile(
      file: enteFile,
      collectionID: 14,
      encryptedKey: "encrypted-key",
      keyDecryptionNonce: "key-nonce",
      data: _commitData,
      pubMagicMetadata: {"version": 1},
    );

    expect(result, same(enteFile));
    expect(enteFile.uploadedFileID, 11);
    expect(enteFile.collectionID, 14);
    expect(enteFile.updationTime, 12);
    expect(enteFile.ownerID, 13);
    expect(enteFile.encryptedKey, "encrypted-key");
    expect(enteFile.keyDecryptionNonce, "key-nonce");
    expect(enteFile.fileDecryptionHeader, "file-header");
    expect(enteFile.thumbnailDecryptionHeader, "thumb-header");
    expect(enteFile.metadataDecryptionHeader, "metadata-header");
    expect(fixture.gateway.createRequests.single, _expectedCreateRequest);
  });

  test(
    "create retries no-response failures four times with 3s delays",
    () async {
      final fixture = _Fixture();
      fixture.gateway.createResults.addAll([
        _dioError(),
        _dioError(),
        _dioError(),
        {"id": 1, "updationTime": 2, "ownerID": 3},
      ]);

      await fixture.transport.createFile(
        file: EnteFile()..localID = "local",
        collectionID: 1,
        encryptedKey: "key",
        keyDecryptionNonce: "nonce",
        data: _commitData,
      );

      expect(fixture.gateway.createRequests, hasLength(4));
      expect(
        fixture.gateway.createRequests,
        everyElement(_expectedCreateRequestWithoutPublicMetadata),
      );
      expect(fixture.delays, [
        UploadTransport.apiRetryDelay,
        UploadTransport.apiRetryDelay,
        UploadTransport.apiRetryDelay,
      ]);
    },
  );

  test("create copies public metadata for every retry", () async {
    final fixture = _Fixture();
    fixture.gateway
      ..clearReceivedPublicMetadata = true
      ..createResults.addAll([
        _dioError(),
        {"id": 1, "updationTime": 2, "ownerID": 3},
      ]);
    final publicMetadata = <String, dynamic>{"version": 1};

    await fixture.transport.createFile(
      file: EnteFile()..localID = "local",
      collectionID: 14,
      encryptedKey: "encrypted-key",
      keyDecryptionNonce: "key-nonce",
      data: _commitData,
      pubMagicMetadata: publicMetadata,
    );

    expect(
      fixture.gateway.createRequests,
      everyElement(_expectedCreateRequest),
    );
    expect(publicMetadata, {"version": 1});
  });

  test("create maps 413 and create/update clear on 426", () async {
    final tooLarge = _Fixture()
      ..gateway.createResults.add(_dioError(statusCode: 413));
    await expectLater(
      tooLarge.transport.createFile(
        file: EnteFile()..localID = "local",
        collectionID: 1,
        encryptedKey: "key",
        keyDecryptionNonce: "nonce",
        data: _commitData,
      ),
      throwsA(isA<FileTooLargeForPlanError>()),
    );

    final createStorage = _Fixture()
      ..gateway.createResults.add(_dioError(statusCode: 426));
    await expectLater(
      createStorage.transport.createFile(
        file: EnteFile()..localID = "local",
        collectionID: 1,
        encryptedKey: "key",
        keyDecryptionNonce: "nonce",
        data: _commitData,
      ),
      throwsA(isA<StorageLimitExceededError>()),
    );
    expect(
      createStorage.clearedErrors.single,
      isA<StorageLimitExceededError>(),
    );

    final updateStorage = _Fixture()
      ..gateway.updateResults.add(_dioError(statusCode: 426));
    await expectLater(
      updateStorage.transport.updateFile(
        file: EnteFile()
          ..localID = "local"
          ..uploadedFileID = 1,
        data: _commitData,
      ),
      throwsA(isA<StorageLimitExceededError>()),
    );
    expect(
      updateStorage.clearedErrors.single,
      isA<StorageLimitExceededError>(),
    );
  });

  test("create does not retry a server response failure", () async {
    final fixture = _Fixture();
    final error = _dioError(statusCode: 500);
    fixture.gateway.createResults.add(error);

    await expectLater(
      fixture.transport.createFile(
        file: EnteFile()..localID = "local",
        collectionID: 1,
        encryptedKey: "key",
        keyDecryptionNonce: "nonce",
        data: _commitData,
      ),
      throwsA(same(error)),
    );

    expect(fixture.gateway.createRequests, hasLength(1));
    expect(fixture.delays, isEmpty);
  });

  test("create leaves 402 response failures unchanged", () async {
    final fixture = _Fixture();
    final error = _dioError(statusCode: 402);
    fixture.gateway.createResults.add(error);

    await expectLater(
      fixture.transport.createFile(
        file: EnteFile()..localID = "local",
        collectionID: 1,
        encryptedKey: "key",
        keyDecryptionNonce: "nonce",
        data: _commitData,
      ),
      throwsA(same(error)),
    );

    expect(fixture.gateway.createRequests, hasLength(1));
    expect(fixture.clearedErrors, isEmpty);
  });

  test("update retries and applies only update response fields", () async {
    final fixture = _Fixture();
    fixture.gateway.updateResults.addAll([
      _dioError(),
      _dioError(),
      _dioError(),
      {"id": 20, "updationTime": 21},
    ]);
    final enteFile = EnteFile()
      ..localID = "local"
      ..uploadedFileID = 10
      ..ownerID = 30
      ..collectionID = 31
      ..encryptedKey = "existing-key"
      ..keyDecryptionNonce = "existing-nonce";

    final result = await fixture.transport.updateFile(
      file: enteFile,
      data: _commitData,
    );

    expect(result, same(enteFile));
    expect(enteFile.uploadedFileID, 20);
    expect(enteFile.updationTime, 21);
    expect(enteFile.ownerID, 30);
    expect(enteFile.collectionID, 31);
    expect(enteFile.encryptedKey, "existing-key");
    expect(enteFile.keyDecryptionNonce, "existing-nonce");
    expect(enteFile.fileDecryptionHeader, "file-header");
    expect(enteFile.thumbnailDecryptionHeader, "thumb-header");
    expect(enteFile.metadataDecryptionHeader, "metadata-header");
    expect(fixture.gateway.updateRequests, hasLength(4));
    expect(
      fixture.gateway.updateRequests,
      everyElement(_expectedUpdateRequest),
    );
    expect(fixture.delays, [
      UploadTransport.apiRetryDelay,
      UploadTransport.apiRetryDelay,
      UploadTransport.apiRetryDelay,
    ]);
  });

  test("update leaves response failures unchanged", () async {
    for (final statusCode in [402, 413, 500]) {
      final fixture = _Fixture();
      final error = _dioError(statusCode: statusCode);
      fixture.gateway.updateResults.add(error);

      await expectLater(
        fixture.transport.updateFile(
          file: EnteFile()
            ..localID = "local"
            ..uploadedFileID = 1,
          data: _commitData,
        ),
        throwsA(same(error)),
      );

      expect(fixture.gateway.updateRequests, hasLength(1));
      expect(fixture.delays, isEmpty);
      expect(fixture.clearedErrors, isEmpty);
    }
  });
}

const _commitData = UploadCommitData(
  fileObjectKey: "file-key",
  fileDecryptionHeader: "file-header",
  fileSize: 100,
  thumbnailObjectKey: "thumb-key",
  thumbnailDecryptionHeader: "thumb-header",
  thumbnailSize: 10,
  encryptedMetadata: "metadata",
  metadataDecryptionHeader: "metadata-header",
);

const _expectedCreateRequest = <String, dynamic>{
  "collectionID": 14,
  "encryptedKey": "encrypted-key",
  "keyDecryptionNonce": "key-nonce",
  "fileObjectKey": "file-key",
  "fileDecryptionHeader": "file-header",
  "fileSize": 100,
  "thumbnailObjectKey": "thumb-key",
  "thumbnailDecryptionHeader": "thumb-header",
  "thumbnailSize": 10,
  "encryptedMetadata": "metadata",
  "metadataDecryptionHeader": "metadata-header",
  "pubMagicMetadata": <String, dynamic>{"version": 1},
};

const _expectedCreateRequestWithoutPublicMetadata = <String, dynamic>{
  "collectionID": 1,
  "encryptedKey": "key",
  "keyDecryptionNonce": "nonce",
  "fileObjectKey": "file-key",
  "fileDecryptionHeader": "file-header",
  "fileSize": 100,
  "thumbnailObjectKey": "thumb-key",
  "thumbnailDecryptionHeader": "thumb-header",
  "thumbnailSize": 10,
  "encryptedMetadata": "metadata",
  "metadataDecryptionHeader": "metadata-header",
  "pubMagicMetadata": null,
};

const _expectedUpdateRequest = <String, dynamic>{
  "fileID": 10,
  "fileObjectKey": "file-key",
  "fileDecryptionHeader": "file-header",
  "fileSize": 100,
  "thumbnailObjectKey": "thumb-key",
  "thumbnailDecryptionHeader": "thumb-header",
  "thumbnailSize": 10,
  "encryptedMetadata": "metadata",
  "metadataDecryptionHeader": "metadata-header",
};

class _Fixture {
  _Fixture() {
    transport = UploadTransport(
      dio,
      gateway,
      shouldUseUploadProxy: () => useProxy,
      clearQueue: clearedErrors.add,
      delay: (duration) async => delays.add(duration),
    );
  }

  final dio = _FakeDio();
  final gateway = _FakeGateway();
  final clearedErrors = <Error>[];
  final delays = <Duration>[];
  bool useProxy = false;
  late final UploadTransport transport;
}

class _FakeDio extends Fake implements Dio {
  final putFailures = Queue<DioException>();
  final putPaths = <String>[];
  final payloads = <List<int>>[];
  final headers = <Map<String, dynamic>>[];
  void Function()? onPutFailure;

  @override
  Future<Response<T>> put<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    putPaths.add(path);
    headers.add(Map<String, dynamic>.from(options?.headers ?? const {}));
    final payload = await (data! as Stream<List<int>>).fold<List<int>>(
      [],
      (bytes, chunk) => bytes..addAll(chunk),
    );
    payloads.add(payload);
    onSendProgress?.call(payload.length, payload.length);
    if (putFailures.isNotEmpty) {
      final error = putFailures.removeFirst();
      onPutFailure?.call();
      throw error;
    }
    return Response<T>(requestOptions: RequestOptions(path: path));
  }
}

class _FakeGateway extends Fake implements FileUploadGateway {
  final uploadURLs = Queue<UploadURL>();
  final uploadURLFailures = Queue<DioException>();
  final uploadURLRequests = <({int contentLength, String contentMd5})>[];
  final createResults = Queue<Object>();
  final createRequests = <Map<String, dynamic>>[];
  final updateResults = Queue<Object>();
  final updateRequests = <Map<String, dynamic>>[];
  bool clearReceivedPublicMetadata = false;

  @override
  Future<UploadURL> getUploadUrl({
    required int contentLength,
    required String contentMd5,
  }) async {
    uploadURLRequests.add((
      contentLength: contentLength,
      contentMd5: contentMd5,
    ));
    if (uploadURLFailures.isNotEmpty) {
      throw uploadURLFailures.removeFirst();
    }
    return uploadURLs.removeFirst();
  }

  @override
  Future<Map<String, dynamic>> createFile({
    required int collectionID,
    required String encryptedKey,
    required String keyDecryptionNonce,
    required String fileObjectKey,
    required String fileDecryptionHeader,
    required int fileSize,
    required String thumbnailObjectKey,
    required String thumbnailDecryptionHeader,
    required int thumbnailSize,
    required String encryptedMetadata,
    required String metadataDecryptionHeader,
    Map<String, dynamic>? pubMagicMetadata,
  }) async {
    createRequests.add({
      "collectionID": collectionID,
      "encryptedKey": encryptedKey,
      "keyDecryptionNonce": keyDecryptionNonce,
      "fileObjectKey": fileObjectKey,
      "fileDecryptionHeader": fileDecryptionHeader,
      "fileSize": fileSize,
      "thumbnailObjectKey": thumbnailObjectKey,
      "thumbnailDecryptionHeader": thumbnailDecryptionHeader,
      "thumbnailSize": thumbnailSize,
      "encryptedMetadata": encryptedMetadata,
      "metadataDecryptionHeader": metadataDecryptionHeader,
      "pubMagicMetadata": pubMagicMetadata == null
          ? null
          : Map<String, dynamic>.of(pubMagicMetadata),
    });
    if (clearReceivedPublicMetadata) {
      pubMagicMetadata?.clear();
    }
    final result = createResults.removeFirst();
    if (result is DioException) throw result;
    return result as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> updateFile({
    required int fileID,
    required String fileObjectKey,
    required String fileDecryptionHeader,
    required int fileSize,
    required String thumbnailObjectKey,
    required String thumbnailDecryptionHeader,
    required int thumbnailSize,
    required String encryptedMetadata,
    required String metadataDecryptionHeader,
  }) async {
    updateRequests.add({
      "fileID": fileID,
      "fileObjectKey": fileObjectKey,
      "fileDecryptionHeader": fileDecryptionHeader,
      "fileSize": fileSize,
      "thumbnailObjectKey": thumbnailObjectKey,
      "thumbnailDecryptionHeader": thumbnailDecryptionHeader,
      "thumbnailSize": thumbnailSize,
      "encryptedMetadata": encryptedMetadata,
      "metadataDecryptionHeader": metadataDecryptionHeader,
    });
    final result = updateResults.removeFirst();
    if (result is DioException) throw result;
    return result as Map<String, dynamic>;
  }
}

DioException _dioError({int? statusCode, Object? data, String? message}) {
  final request = RequestOptions(path: "test");
  return DioException(
    requestOptions: request,
    response: statusCode == null
        ? null
        : Response<dynamic>(
            requestOptions: request,
            statusCode: statusCode,
            data: data,
          ),
    message: message,
  );
}
