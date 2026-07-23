import "package:dio/dio.dart";
import "package:photos/gateways/entity/models/data.dart";
import "package:photos/gateways/entity/models/key.dart";
import "package:photos/gateways/entity/models/type.dart";

class EntityGateway {
  final Dio _enteDio;

  EntityGateway(this._enteDio);

  Future<void> createKey(
    EntityType entityType,
    String encKey,
    String header,
  ) async {
    await _enteDio.post(
      "/user-entity/key",
      data: {"type": entityType.name, "encryptedKey": encKey, "header": header},
    );
  }

  Future<EntityKey> getKey(EntityType type) async {
    try {
      final response = await _enteDio.get(
        "/user-entity/key",
        queryParameters: {"type": type.name},
      );
      return EntityKey.fromMap(response.data);
    } on DioException catch (e) {
      if (e.response != null && (e.response!.statusCode ?? 0) == 404) {
        throw EntityKeyNotFound();
      } else {
        rethrow;
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<EntityData> createEntity(
    EntityType type,
    String? id,
    String encryptedData,
    String header,
  ) async {
    final response = await _enteDio.post(
      "/user-entity/entity",
      data: {
        "encryptedData": encryptedData,
        "id": ?id,
        "header": header,
        "type": type.name,
      },
    );
    return EntityData.fromMap(response.data);
  }

  Future<EntityData> updateEntity(
    EntityType type,
    String id,
    String encryptedData,
    String header,
  ) async {
    final response = await _enteDio.put(
      "/user-entity/entity",
      data: {
        "id": id,
        "encryptedData": encryptedData,
        "header": header,
        "type": type.name,
      },
    );
    return EntityData.fromMap(response.data);
  }

  Future<void> deleteEntity(String id) async {
    await _enteDio.delete("/user-entity/entity", queryParameters: {"id": id});
  }

  Future<List<EntityData>> getDiff(
    EntityType type,
    int sinceTime, {
    int limit = 500,
  }) async {
    final response = await _enteDio.get(
      "/user-entity/entity/diff",
      queryParameters: {
        "sinceTime": sinceTime,
        "limit": limit,
        "type": type.name,
      },
    );
    final List<EntityData> authEntities = <EntityData>[];
    final diff = response.data["diff"] as List;
    for (var entry in diff) {
      final EntityData entity = EntityData.fromMap(entry);
      authEntities.add(entity);
    }
    return authEntities;
  }
}

class EntityKeyNotFound extends Error {}
