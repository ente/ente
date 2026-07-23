import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:ente_crypto_api/ente_crypto_api.dart';
import 'package:ente_network/network.dart';
import 'package:ente_sharing/errors.dart';
import 'package:ente_sharing/models/user.dart';
import 'package:logging/logging.dart';

class CollectionSharingService {
  final _logger = Logger('CollectionSharingService');
  final _enteDio = Network.instance.enteDio;

  static final CollectionSharingService instance =
      CollectionSharingService._privateConstructor();

  CollectionSharingService._privateConstructor();

  /// Share a collection with a user
  Future<List<User>> share(
    int collectionID,
    String email,
    String publicKey,
    String role,
    Uint8List collectionKey,
    Uint8List encryptedKey,
  ) async {
    final params = {
      'collectionID': collectionID,
      'email': email,
      'encryptedKey': CryptoUtil.bin2base64(encryptedKey),
      'role': role,
    };

    try {
      final response = await _enteDio.post('/collections/share', data: params);
      final sharees = <User>[];
      for (final user in response.data["sharees"]) {
        sharees.add(User.fromMap(user));
      }
      return sharees;
    } on DioException catch (e) {
      if (e.response?.statusCode == 402) {
        throw SharingNotPermittedForFreeAccountsError();
      }
      rethrow;
    }
  }

  /// Unshare a collection with a user
  Future<List<User>> unshare(int collectionID, String email) async {
    try {
      final response = await _enteDio.post(
        "/collections/unshare",
        data: {"collectionID": collectionID, "email": email},
      );
      final sharees = <User>[];
      for (final user in response.data["sharees"]) {
        sharees.add(User.fromMap(user));
      }
      return sharees;
    } catch (e) {
      _logger.severe('Failed to unshare collection', e);
      rethrow;
    }
  }

  /// Create a public sharing URL for a collection
  Future<Response> createShareUrl(int collectionID, bool enableCollect) async {
    try {
      final response = await _enteDio.post(
        '/collections/share-url',
        data: {
          'collectionID': collectionID,
          'enableCollect': enableCollect,
          "enableJoin": true,
        },
      );
      return response;
    } on DioException catch (e) {
      if (e.response?.statusCode == 402) {
        throw SharingNotPermittedForFreeAccountsError();
      }
      rethrow;
    } catch (e, s) {
      _logger.severe("failed to create share URL", e, s);
      rethrow;
    }
  }

  /// Disable public sharing URL for a collection
  Future<void> disableShareUrl(int collectionID) async {
    try {
      await _enteDio.delete(
        "/collections/share-url/" + collectionID.toString(),
      );
    } on DioException catch (e) {
      _logger.info(e);
      rethrow;
    }
  }

  Future<Response> updateShareUrl(
    int collectionID,
    Map<String, dynamic> prop,
  ) async {
    prop.putIfAbsent('collectionID', () => collectionID);
    try {
      final response = await _enteDio.put(
        "/collections/share-url",
        data: json.encode(prop),
      );
      return response;
    } on DioException catch (e) {
      if (e.response?.statusCode == 402) {
        throw SharingNotPermittedForFreeAccountsError();
      }
      if (e.response?.statusCode == 403 &&
          e.response?.data?['code'] == 'LINK_EDIT_NOT_ALLOWED') {
        throw LinkEditNotAllowedError();
      }
      rethrow;
    } catch (e, s) {
      _logger.severe("failed to update ShareUrl", e, s);
      rethrow;
    }
  }

  /// Leave a shared collection
  Future<void> leaveCollection(int collectionID) async {
    try {
      await _enteDio.post("/collections/leave/$collectionID");
    } catch (e) {
      _logger.severe('Failed to leave collection', e);
      rethrow;
    }
  }
}
