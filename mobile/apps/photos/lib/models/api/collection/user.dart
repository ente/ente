import "dart:convert";

// TODO(neeraj): Move User and UserSuggestion to a shared package.
class User {
  final int id;
  String email;
  final String? label;
  String? role;

  User({required this.id, required this.email, this.label, this.role});

  bool get isViewer => role == null || role?.toUpperCase() == 'VIEWER';

  bool get isCollaborator =>
      role != null && role?.toUpperCase() == 'COLLABORATOR';

  bool get isAdmin => role != null && role?.toUpperCase() == 'ADMIN';

  Map<String, dynamic> toMap() {
    return {'id': id, 'email': email, "role": role};
  }

  static User fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] as int,
      email: map['email'] as String,
      role: map['role'] ?? 'VIEWER',
    );
  }

  String toJson() => json.encode(toMap());

  factory User.fromJson(String source) => User.fromMap(json.decode(source));
}

class UserSuggestion {
  const UserSuggestion(this.email, {this.userID, this.label});

  factory UserSuggestion.fromUser(User user) =>
      UserSuggestion(user.email, userID: user.id, label: user.label);

  final int? userID;
  final String email;
  final String? label;
}
