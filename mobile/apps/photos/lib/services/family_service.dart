import 'package:dio/dio.dart';
import 'package:logging/logging.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/events/user_details_changed_event.dart';
import 'package:photos/models/user_details.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/account/user_service.dart';

class FamilyInviteFailure {
  const FamilyInviteFailure({required this.email, required this.error});

  final String email;
  final Object error;
}

class FamilyInviteResult {
  const FamilyInviteResult({required this.failures});

  final List<FamilyInviteFailure> failures;

  bool get hasFailures => failures.isNotEmpty;
}

class FamilyService {
  FamilyService._privateConstructor();

  static final FamilyService instance = FamilyService._privateConstructor();

  final _logger = Logger("FamilyService");

  Future<UserDetails> refreshUserDetails() async {
    final details = await UserService.instance.getUserDetailsV2(
      memoryCount: false,
    );
    Bus.instance.fire(UserDetailsChangedEvent());
    return details;
  }

  Future<FamilyInviteResult> inviteMembers({
    required UserDetails userDetails,
    required List<String> emails,
  }) async {
    if (userDetails.familyData == null) {
      await usersGateway.createFamily();
    }

    final failures = <FamilyInviteFailure>[];
    for (final email in emails) {
      try {
        await usersGateway.inviteFamilyMember(email: email);
      } catch (error, stackTrace) {
        _logger.warning("Failed to invite $email", error, stackTrace);
        failures.add(FamilyInviteFailure(email: email, error: error));
      }
    }

    return FamilyInviteResult(failures: failures);
  }

  Future<void> resendInvite(FamilyMember member) async {
    await usersGateway.inviteFamilyMember(email: member.email);
  }

  Future<void> revokeInvite(FamilyMember member) async {
    await usersGateway.revokeFamilyInvite(member.id);
  }

  Future<void> removeMember(FamilyMember member) async {
    await usersGateway.removeFamilyMember(member.id);
  }

  Future<UserDetails> updateMemberStorageLimit({
    required FamilyMember member,
    int? storageLimit,
  }) async {
    await usersGateway.updateFamilyMemberStorage(
      id: member.id,
      storageLimit: storageLimit,
    );
    return refreshUserDetails();
  }

  Future<UserDetails> leaveFamily() async {
    await UserService.instance.leaveFamilyPlan();
    return refreshUserDetails();
  }

  Future<void> closeFamily(UserDetails userDetails) async {
    final members = userDetails.familyData?.members;
    if (members == null) {
      return;
    }

    for (final member in members) {
      if (member.email.trim() == userDetails.email.trim()) {
        continue;
      }
      if (member.isPending) {
        await revokeInvite(member);
      } else if (member.isActive) {
        await removeMember(member);
      }
    }
  }

  static bool isNotFoundError(Object error) {
    return error is DioException && error.response?.statusCode == 404;
  }
}
