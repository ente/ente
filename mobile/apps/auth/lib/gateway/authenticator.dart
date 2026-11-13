import 'package:dio/dio.dart';
import 'package:ente_auth/core/errors.dart';
import 'package:ente_auth/models/authenticator/auth_entity.dart';
import 'package:ente_auth/models/authenticator/auth_key.dart';
import 'package:ente_network/network.dart';

class AuthenticatorGateway {
  late Dio _enteDio;

  AuthenticatorGateway() {
    _enteDio = Network.instance.enteDio;
  }

  Future<void> createKey(String encKey, String header) async {
    await _enteDio.post(
      "/authenticator/key",
      data: {"encryptedKey": encKey, "header": header},
    );
  }

  Future<AuthKey> getKey() async {
    try {
      final response = await _enteDio.get("/authenticator/key");
      return AuthKey.fromMap(response.data);
    } on DioException catch (e) {
      if (e.response != null && (e.response!.statusCode ?? 0) == 404) {
        throw AuthenticatorKeyNotFound();
      } else {
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<AuthEntity> createEntity(String encryptedData, String header) async {
    final response = await _enteDio.post(
      "/authenticator/entity",
      data: {"encryptedData": encryptedData, "header": header},
    );
    return AuthEntity.fromMap(response.data);
  }

  Future<void> updateEntity(
    String id,
    String encryptedData,
    String header,
  ) async {
    await _enteDio.put(
      "/authenticator/entity",
      data: {"id": id, "encryptedData": encryptedData, "header": header},
    );
  }

  Future<void> deleteEntity(String id) async {
    await _enteDio.delete("/authenticator/entity", queryParameters: {"id": id});
  }

  Future<(List<AuthEntity>, int?)> getDiff(
    int sinceTime, {
    int limit = 500,
  }) async {
    try {
      final response = await _enteDio.get(
        "/authenticator/entity/diff",
        queryParameters: {"sinceTime": sinceTime, "limit": limit},
      );
      final List<AuthEntity> authEntities = <AuthEntity>[];
      final diff = response.data["diff"] as List;
      final int? unixTimeInMicroSeconds = response.data["timestamp"] as int?;
      for (var entry in diff) {
        final AuthEntity entity = AuthEntity.fromMap(entry);
        authEntities.add(entity);
      }
      return (authEntities, unixTimeInMicroSeconds);
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        throw UnauthorizedError();
      } else {
        rethrow;
      }
    }
  }
}
