class SetupSRPRequest {
  final String srpUserID;
  final String srpSalt;
  final String srpVerifier;
  final String srpA;
  final bool isUpdate;

  SetupSRPRequest({
    required this.srpUserID,
    required this.srpSalt,
    required this.srpVerifier,
    required this.srpA,
    required this.isUpdate,
  });

  Map<String, dynamic> toMap() {
    return {
      'srpUserID': srpUserID.toString(),
      'srpSalt': srpSalt,
      'srpVerifier': srpVerifier,
      'srpA': srpA,
      'isUpdate': isUpdate,
    };
  }

  factory SetupSRPRequest.fromJson(Map<String, dynamic> json) {
    return SetupSRPRequest(
      srpUserID: json['srpUserID'],
      srpSalt: json['srpSalt'],
      srpVerifier: json['srpVerifier'],
      srpA: json['srpA'],
      isUpdate: json['isUpdate'],
    );
  }
}

class SetupSRPResponse {
  final String setupID;
  final String srpB;

  SetupSRPResponse({required this.setupID, required this.srpB});

  Map<String, dynamic> toMap() {
    return {'setupID': setupID.toString(), 'srpB': srpB};
  }

  factory SetupSRPResponse.fromJson(Map<String, dynamic> json) {
    return SetupSRPResponse(setupID: json['setupID'], srpB: json['srpB']);
  }
}

class CompleteSRPSetupRequest {
  final String setupID;
  final String srpM1;

  CompleteSRPSetupRequest({required this.setupID, required this.srpM1});

  Map<String, dynamic> toMap() {
    return {'setupID': setupID.toString(), 'srpM1': srpM1};
  }

  factory CompleteSRPSetupRequest.fromJson(Map<String, dynamic> json) {
    return CompleteSRPSetupRequest(
      setupID: json['setupID'],
      srpM1: json['srpM1'],
    );
  }
}

class SrpAttributes {
  final String srpUserID;
  final String srpSalt;
  final int memLimit;
  final int opsLimit;
  final String kekSalt;
  final bool isEmailMFAEnabled;

  SrpAttributes({
    required this.srpUserID,
    required this.srpSalt,
    required this.memLimit,
    required this.opsLimit,
    required this.kekSalt,
    required this.isEmailMFAEnabled,
  });

  factory SrpAttributes.fromMap(Map<String, dynamic> map) {
    return SrpAttributes(
      srpUserID: map['attributes']['srpUserID'],
      srpSalt: map['attributes']['srpSalt'],
      memLimit: map['attributes']['memLimit'],
      opsLimit: map['attributes']['opsLimit'],
      kekSalt: map['attributes']['kekSalt'],
      isEmailMFAEnabled: map['attributes']['isEmailMFAEnabled'],
    );
  }
}

class CompleteSRPSetupResponse {
  final String setupID;
  final String srpM2;

  CompleteSRPSetupResponse({required this.setupID, required this.srpM2});

  Map<String, dynamic> toMap() {
    return {'setupID': setupID, 'srpM2': srpM2};
  }

  factory CompleteSRPSetupResponse.fromJson(Map<String, dynamic> json) {
    return CompleteSRPSetupResponse(
      setupID: json['setupID'],
      srpM2: json['srpM2'],
    );
  }
}
