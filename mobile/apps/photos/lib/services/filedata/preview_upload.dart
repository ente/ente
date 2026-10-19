import "dart:io";

import "package:dio/dio.dart";
import "package:ente_pure_utils/ente_pure_utils.dart";
import "package:photos/gateways/files/file_data_gateway.dart";

Future<(String, int)> uploadVideoPreview(
  File preview, {
  required int fileID,
  required FileDataGateway gateway,
  required Dio dio,
  required bool useUploadV2,
  CancelToken? cancelToken,
}) async {
  final objectSize = await preview.length();
  final contentMd5 = useUploadV2 ? await computeMd5(preview.path) : null;
  final upload = contentMd5 != null
      ? await gateway.getPreviewUploadUrlV2(
          fileID: fileID,
          type: "vid_preview",
          contentLength: objectSize,
          contentMd5: contentMd5,
          cancelToken: cancelToken,
        )
      : await gateway.getPreviewUploadUrl(
          fileID: fileID,
          type: "vid_preview",
          cancelToken: cancelToken,
        );
  await dio.put(
    upload.url,
    data: preview.openRead(),
    options: Options(
      headers: {
        Headers.contentLengthHeader: objectSize,
        "Content-MD5": ?contentMd5,
      },
    ),
    cancelToken: cancelToken,
  );
  return (upload.objectID, objectSize);
}
