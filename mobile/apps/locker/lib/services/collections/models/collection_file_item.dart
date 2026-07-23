import 'dart:convert';

class CollectionFileItem {
  final int id;
  final String encryptedKey;
  final String keyDecryptionNonce;

  CollectionFileItem(this.id, this.encryptedKey, this.keyDecryptionNonce);

  CollectionFileItem copyWith({
    int? id,
    String? encryptedKey,
    String? keyDecryptionNonce,
  }) {
    return CollectionFileItem(
      id ?? this.id,
      encryptedKey ?? this.encryptedKey,
      keyDecryptionNonce ?? this.keyDecryptionNonce,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'encryptedKey': encryptedKey,
      'keyDecryptionNonce': keyDecryptionNonce,
    };
  }

  static CollectionFileItem fromMap(Map<String, dynamic> map) {
    return CollectionFileItem(
      map['id'],
      map['encryptedKey'],
      map['keyDecryptionNonce'],
    );
  }

  String toJson() => json.encode(toMap());

  factory CollectionFileItem.fromJson(String source) =>
      CollectionFileItem.fromMap(json.decode(source));

  @override
  String toString() =>
      'CollectionFileItem(id: $id, encryptedKey: $encryptedKey, keyDecryptionNonce: $keyDecryptionNonce)';

  @override
  bool operator ==(Object o) {
    if (identical(this, o)) return true;

    return o is CollectionFileItem &&
        o.id == id &&
        o.encryptedKey == encryptedKey &&
        o.keyDecryptionNonce == keyDecryptionNonce;
  }

  @override
  int get hashCode =>
      id.hashCode ^ encryptedKey.hashCode ^ keyDecryptionNonce.hashCode;
}
