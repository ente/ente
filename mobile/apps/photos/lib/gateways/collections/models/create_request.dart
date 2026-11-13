import "package:photos/gateways/collections/models/metadata.dart";
import 'package:photos/models/collection/collection.dart';

class CreateRequest {
  String encryptedKey;
  String keyDecryptionNonce;
  String encryptedName;
  String nameDecryptionNonce;
  CollectionType type;
  CollectionAttributes? attributes;
  MetadataRequest? magicMetadata;

  CreateRequest({
    required this.encryptedKey,
    required this.keyDecryptionNonce,
    required this.encryptedName,
    required this.nameDecryptionNonce,
    required this.type,
    this.attributes,
    this.magicMetadata,
  });

  CreateRequest copyWith({
    String? encryptedKey,
    String? keyDecryptionNonce,
    String? encryptedName,
    String? nameDecryptionNonce,
    CollectionType? type,
    CollectionAttributes? attributes,
    MetadataRequest? magicMetadata,
  }) => CreateRequest(
    encryptedKey: encryptedKey ?? this.encryptedKey,
    keyDecryptionNonce: keyDecryptionNonce ?? this.keyDecryptionNonce,
    encryptedName: encryptedName ?? this.encryptedName,
    nameDecryptionNonce: nameDecryptionNonce ?? this.nameDecryptionNonce,
    type: type ?? this.type,
    attributes: attributes ?? this.attributes,
    magicMetadata: magicMetadata ?? this.magicMetadata,
  );

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    map['encryptedKey'] = encryptedKey;
    map['keyDecryptionNonce'] = keyDecryptionNonce;
    map['encryptedName'] = encryptedName;
    map['nameDecryptionNonce'] = nameDecryptionNonce;
    map['type'] = typeToString(type);
    if (attributes != null) {
      map['attributes'] = attributes!.toMap();
    }
    if (magicMetadata != null) {
      map['magicMetadata'] = magicMetadata!.toJson();
    }
    return map;
  }
}
