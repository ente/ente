import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:logging/logging.dart';

class MultipartUploader {
  static const partSize = 20 * 1024 * 1024;
  static const _maximumAttempts = 3;

  final _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 15)));
  final _logger = Logger('MultipartUploader');

  Future<String> upload(
    File file,
    int fileSize,
    List<String> partMd5s,
    MultipartUploadURLs urls,
  ) async {
    final partCount = (fileSize / partSize).ceil();
    if (urls.partURLs.length != partCount || partMd5s.length != partCount) {
      throw Exception('Multipart upload part count mismatch');
    }

    final parts = <String>[];
    for (var i = 0; i < partCount; i++) {
      final start = i * partSize;
      final end = (start + partSize).clamp(0, fileSize);
      _logger.info('Uploading part ${i + 1}/$partCount');
      final response = await _retry(
        () => _dio.put<String>(
          urls.partURLs[i],
          data: file.openRead(start, end),
          options: Options(
            responseType: ResponseType.plain,
            contentType: 'application/octet-stream',
            headers: {
              Headers.contentLengthHeader: end - start,
              'Content-MD5': partMd5s[i],
            },
          ),
        ),
      );
      final eTag = response.headers.value('etag');
      if (eTag == null || eTag.isEmpty) {
        throw Exception('ETAG_MISSING');
      }
      parts.add(
        '<Part><PartNumber>${i + 1}</PartNumber>'
        '<ETag>${const HtmlEscape(HtmlEscapeMode.element).convert(eTag)}</ETag></Part>',
      );
    }

    await _retry(() async {
      final response = await _dio.post<String>(
        urls.completeURL,
        data:
            '<CompleteMultipartUpload>${parts.join()}</CompleteMultipartUpload>',
        options: Options(
          contentType: 'text/xml',
          responseType: ResponseType.plain,
        ),
      );
      if (!(response.data?.contains('<CompleteMultipartUploadResult') ??
          false)) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          message: 'Multipart upload completion failed',
        );
      }
      return response;
    });
    return urls.objectKey;
  }

  Future<Response<String>> _retry(
    Future<Response<String>> Function() request,
  ) async {
    for (var attempt = 1; ; attempt++) {
      try {
        return await request();
      } on DioException {
        if (attempt >= _maximumAttempts) rethrow;
        _logger.info(
          'Upload request failed, retrying (${attempt + 1}/$_maximumAttempts)',
        );
      }
    }
  }
}

class MultipartUploadURLs {
  final String objectKey;
  final List<String> partURLs;
  final String completeURL;

  MultipartUploadURLs.fromMap(Map<String, dynamic> map)
    : objectKey = map['objectKey'] as String,
      partURLs = (map['partURLs'] as List).cast<String>(),
      completeURL = map['completeURL'] as String;
}
