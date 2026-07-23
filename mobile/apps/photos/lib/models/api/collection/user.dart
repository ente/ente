import "dart:convert";

class User {
  int? id;
  String email;
  @Deprecated(
    "Use displayName() extension method instead. Note: Some early users have"
    " value in name field.",
  )
  String? name;
  String? role;

  User({this.id, required this.email, this.name, this.role});

  bool get isViewer => role == null || role?.toUpperCase() == 'VIEWER';

  bool get isCollaborator =>
      role != null && role?.toUpperCase() == 'COLLABORATOR';

  bool get isAdmin => role != null && role?.toUpperCase() == 'ADMIN';

  Map<String, dynamic> toMap() {
    // ignore: deprecated_member_use_from_same_package
    return {'id': id, 'email': email, 'name': name, "role": role};
  }

  static User fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'],
      email: map['email'],
      name: map['name'],
      role: map['role'] ?? 'VIEWER',
    );
  }

  String toJson() => json.encode(toMap());

  factory User.fromJson(String source) => User.fromMap(json.decode(source));
}
