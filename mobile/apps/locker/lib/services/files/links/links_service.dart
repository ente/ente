import "package:locker/services/authenticated_session.dart";
import "package:locker/services/collections/collections_service.dart";
import "package:locker/services/files/links/links_client.dart";
import "package:locker/services/files/links/models/shareable_link.dart";
import "package:locker/services/files/sync/models/file.dart";
import "package:locker/src/rust/third_party/ente_frb_lib/locker.dart";

class LinksService {
  LinksService._();

  static final LinksService instance = LinksService._();

  late final LinksClient _client;

  Future<void> init() async {
    _client = LinksClient.instance;
  }

  Future<ShareableLink> getOrCreateLink(EnteFile file) async {
    final fileKey = await CollectionService.instance.getFileKey(file);
    final session = authenticatedSession();
    final secretPayload = await prepareFileLink(
      session: session,
      fileKey: fileKey,
    );

    final link = await _client.getOrCreateLink(
      file.uploadedFileID!,
      metadata: {
        'encryptedFileKey': secretPayload.encryptedFileKey,
        'encryptedFileKeyNonce': secretPayload.encryptedFileKeyNonce,
        'kdfNonce': secretPayload.kdfNonce,
        'kdfMemLimit': secretPayload.kdfMemLimit.toInt(),
        'kdfOpsLimit': secretPayload.kdfOpsLimit,
        'encryptedShareKey': secretPayload.encryptedShareKey,
      },
    );
    final encryptedShareKey = link.encryptedShareKey;
    final fragmentSecret = encryptedShareKey == null
        ? secretPayload.fragment
        : await openFileLinkSecret(
            session: session,
            encryptedShareKey: encryptedShareKey,
          );
    link.fullURL = "${link.url}#$fragmentSecret";
    return link;
  }

  Future<void> deleteLink(int fileID) async {
    await _client.deleteLink(fileID);
  }
}
