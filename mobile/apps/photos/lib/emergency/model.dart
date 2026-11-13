import "package:ente_frb/legacy.dart";
import "package:photos/models/api/collection/user.dart";

export "package:ente_frb/legacy.dart";

extension LegacyContactExtension on LegacyContactRecord {
  bool isPendingInvite() => state == LegacyContactState.invited;

  LegacyContactRecord copyWith({
    LegacyContactState? state,
    int? recoveryNoticeInDays,
  }) => LegacyContactRecord(
    user: user,
    emergencyContact: emergencyContact,
    state: state ?? this.state,
    recoveryNoticeInDays: recoveryNoticeInDays ?? this.recoveryNoticeInDays,
  );
}

extension LegacyUserDisplay on LegacyUser {
  User get asUser => User(id: id, email: email);
}
