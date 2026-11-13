import "package:dio/dio.dart";
import "package:photos/gateways/collections/models/metadata.dart";

class FileMagicGateway {
  final Dio _enteDio;

  FileMagicGateway(this._enteDio);

  Future<void> updateMagicMetadata(
    List<UpdateMagicMetadataRequest> metadataList,
  ) async {
    await _enteDio.put(
      "/files/magic-metadata",
      data: {"metadataList": metadataList},
    );
  }

  Future<void> updatePublicMagicMetadata(
    List<UpdateMagicMetadataRequest> metadataList,
  ) async {
    await _enteDio.put(
      "/files/public-magic-metadata",
      data: {"metadataList": metadataList},
    );
  }
}
