import 'dart:convert';

import "package:freezed_annotation/freezed_annotation.dart";

@immutable
class EntityData {
  final String id;

  // Null for deleted diff entries.
  final String? encryptedData;
  final String? header;
  final bool isDeleted;
  final int createdAt;
  final int updatedAt;
  final int userID;

  const EntityData(
    this.id,
    this.userID,
    this.encryptedData,
    this.header,
    this.isDeleted,
    this.createdAt,
    this.updatedAt,
  );

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userID': userID,
      'encryptedData': encryptedData,
      'header': header,
      'isDeleted': isDeleted,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory EntityData.fromMap(Map<String, dynamic> map) {
    return EntityData(
      map['id'],
      map['userID'],
      map['encryptedData'],
      map['header'],
      map['isDeleted']!,
      map['createdAt']!,
      map['updatedAt']!,
    );
  }

  String toJson() => json.encode(toMap());

  factory EntityData.fromJson(String source) =>
      EntityData.fromMap(json.decode(source));
}
