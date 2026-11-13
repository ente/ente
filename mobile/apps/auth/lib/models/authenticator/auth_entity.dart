import 'dart:convert';

import 'package:flutter/material.dart';

@immutable
class AuthEntity {
  final String id;
  // Null for deleted diff entries.
  final String? encryptedData;
  final String? header;
  final bool isDeleted;
  final int createdAt;
  final int updatedAt;

  AuthEntity(
    this.id,
    this.encryptedData,
    this.header,
    this.isDeleted,
    this.createdAt,
    this.updatedAt,
  );

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'encryptedData': encryptedData,
      'header': header,
      'isDeleted': isDeleted,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory AuthEntity.fromMap(Map<String, dynamic> map) {
    return AuthEntity(
      map['id'],
      map['encryptedData'],
      map['header'],
      map['isDeleted']!,
      map['createdAt']!,
      map['updatedAt']!,
    );
  }

  String toJson() => json.encode(toMap());

  factory AuthEntity.fromJson(String source) =>
      AuthEntity.fromMap(json.decode(source));
}
