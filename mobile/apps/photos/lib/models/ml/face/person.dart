import "package:flutter/foundation.dart";

const Object _personDataUnchanged = Object();

class PersonEntity {
  final String remoteID;
  final PersonData data;
  PersonEntity(this.remoteID, this.data);

  PersonEntity copyWith({String? remoteID, PersonData? data}) {
    return PersonEntity(remoteID ?? this.remoteID, data ?? this.data);
  }
}

class ClusterInfo {
  final String id;
  final Set<String> faces;
  ClusterInfo({required this.id, required this.faces});

  Map<String, dynamic> toJson() => {'id': id, 'faces': faces.toList()};

  factory ClusterInfo.fromJson(Map<String, dynamic> json) {
    return ClusterInfo(
      id: json['id'] as String,
      faces: (json['faces'] as List<dynamic>).map((e) => e as String).toSet(),
    );
  }
}

class PersonData {
  final String name;

  // Use isIgnored; it also handles legacy hidden names.
  final bool isHidden;
  final bool isPinned;
  final bool hideFromMemories;

  String? avatarFaceID;
  List<ClusterInfo> assigned = List<ClusterInfo>.empty();
  List<String> rejectedFaceIDs = List<String>.empty();
  List<int> manuallyAssigned = List<int>.empty();

  // Formatted as yyyy-MM-dd.
  final String? birthDate;

  // Look up the current email by userID; this value can be stale.
  final String? email;
  final int? userID;

  bool hasAvatar() => avatarFaceID != null;

  bool get isIgnored =>
      (isHidden || name.isEmpty || name == '(hidden)' || name == '(ignored)');

  PersonData({
    required this.name,
    this.assigned = const <ClusterInfo>[],
    this.rejectedFaceIDs = const <String>[],
    this.manuallyAssigned = const <int>[],
    this.avatarFaceID,
    this.isHidden = false,
    this.isPinned = false,
    this.hideFromMemories = false,
    this.birthDate,
    this.email,
    this.userID,
  });
  PersonData copyWith({
    String? name,
    List<ClusterInfo>? assigned,
    String? avatarFaceId,
    bool? isHidden,
    bool? isPinned,
    bool? hideFromMemories,
    Object? birthDate = _personDataUnchanged,
    Object? email = _personDataUnchanged,
    Object? userID = _personDataUnchanged,
    List<String>? rejectedFaceIDs,
    List<int>? manuallyAssigned,
  }) {
    return PersonData(
      name: name ?? this.name,
      assigned: assigned ?? this.assigned,
      avatarFaceID: avatarFaceId ?? avatarFaceID,
      isHidden: isHidden ?? this.isHidden,
      isPinned: isPinned ?? this.isPinned,
      hideFromMemories: hideFromMemories ?? this.hideFromMemories,
      birthDate: identical(birthDate, _personDataUnchanged)
          ? this.birthDate
          : birthDate as String?,
      email: identical(email, _personDataUnchanged)
          ? this.email
          : email as String?,
      userID: identical(userID, _personDataUnchanged)
          ? this.userID
          : userID as int?,
      rejectedFaceIDs:
          rejectedFaceIDs ?? List<String>.from(this.rejectedFaceIDs),
      manuallyAssigned:
          manuallyAssigned ?? List<int>.from(this.manuallyAssigned),
    );
  }

  void logStats() {
    if (kDebugMode == false) return;
    final StringBuffer sb = StringBuffer();
    sb.writeln('Person: $name');
    int assignedCount = 0;
    for (final a in assigned) {
      assignedCount += a.faces.length;
    }
    sb.writeln('Assigned: ${assigned.length} withFaces $assignedCount');
    sb.writeln('Rejected faceIDs: ${rejectedFaceIDs.length}');
    sb.writeln('Manual fileIDs: ${manuallyAssigned.length}');
    for (var cluster in assigned) {
      sb.writeln('Cluster: ${cluster.id} - ${cluster.faces.length}');
    }
    debugPrint(sb.toString());
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'assigned': assigned.map((e) => e.toJson()).toList(),
    'rejectedFaceIDs': rejectedFaceIDs,
    'avatarFaceID': avatarFaceID,
    'isHidden': isHidden,
    'isPinned': isPinned,
    'hideFromMemories': hideFromMemories,
    'birthDate': birthDate,
    'email': email,
    'userID': userID,
    'manuallyAssigned': manuallyAssigned,
  };

  factory PersonData.fromJson(Map<String, dynamic> json) {
    final assigned =
        (json['assigned'] == null ||
            json['assigned'].length == 0 ||
            json['assigned'] is! Iterable)
        ? <ClusterInfo>[]
        : List<ClusterInfo>.from(
            json['assigned']
                .where((x) => x is Map<String, dynamic>)
                .map((x) => ClusterInfo.fromJson(x as Map<String, dynamic>)),
          );

    final List<String> rejectedFaceIDs =
        (json['rejectedFaceIDs'] == null || json['rejectedFaceIDs'].length == 0)
        ? <String>[]
        : List<String>.from(json['rejectedFaceIDs']);
    final manualAssignmentData = json['manuallyAssigned'];
    final manuallyAssigned = manualAssignmentData is Iterable
        ? List<int>.from(
            manualAssignmentData.map<int?>((value) {
              if (value is num) return value.toInt();
              return int.tryParse(value.toString());
            }).whereType<int>(),
          )
        : <int>[];
    return PersonData(
      name: (json['name'] as String?) ?? '',
      assigned: assigned,
      rejectedFaceIDs: rejectedFaceIDs,
      manuallyAssigned: manuallyAssigned,
      avatarFaceID: json['avatarFaceID'] as String?,
      isHidden: json['isHidden'] as bool? ?? false,
      isPinned: json['isPinned'] as bool? ?? false,
      hideFromMemories: json['hideFromMemories'] as bool? ?? false,
      birthDate: json['birthDate'] as String?,
      userID: json['userID'] as int?,
      email: json['email'] as String?,
    );
  }
}
