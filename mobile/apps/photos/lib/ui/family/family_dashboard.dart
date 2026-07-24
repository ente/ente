import 'dart:typed_data';

import 'package:ente_components/ente_components.dart';
import 'package:ente_contacts/contacts.dart' as contacts;
import 'package:ente_pure_utils/ente_pure_utils.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:photos/generated/l10n.dart';
import 'package:photos/models/user_details.dart';
import 'package:photos/ui/viewer/people/person_face_widget.dart';
import 'package:photos/utils/avatar_util.dart';

enum FamilyMemberAction {
  saveContact,
  editContact,
  editStorageLimit,
  removeMember,
  resendInvite,
  revokeInvite,
}

AvatarComponentColor familyMemberAvatarComponentColor(FamilyMember member) {
  return avatarComponentColorForIdentity(
    avatarIdentityKey(email: member.email, userID: member.userID),
  );
}

List<FamilyMemberAction> familyMemberActions({
  required bool isAdmin,
  required bool isCurrentUser,
  required FamilyMember member,
  required bool hasSavedContact,
}) {
  if (isCurrentUser) {
    return const [];
  }

  final contactAction = member.userID == null
      ? null
      : hasSavedContact
      ? FamilyMemberAction.editContact
      : FamilyMemberAction.saveContact;

  if (isAdmin) {
    return [
      ?contactAction,
      if (member.isPending) ...[
        FamilyMemberAction.resendInvite,
        FamilyMemberAction.revokeInvite,
      ] else ...[
        FamilyMemberAction.editStorageLimit,
        FamilyMemberAction.removeMember,
      ],
    ];
  }

  if (!member.isActive || contactAction == null) {
    return const [];
  }
  return [contactAction];
}

class FamilyDashboard extends StatelessWidget {
  const FamilyDashboard({
    required this.userDetails,
    required this.members,
    required this.isAdmin,
    required this.contactsByUserId,
    required this.profilePictureBytesByUserId,
    required this.linkedPersonIdsByUserId,
    required this.linkedPersonNamesByUserId,
    required this.onMemberTap,
    required this.onAddMember,
    required this.remainingSlots,
    super.key,
  });

  final UserDetails userDetails;
  final List<FamilyMember> members;
  final bool isAdmin;
  final Map<int, contacts.ContactRecord?> contactsByUserId;
  final Map<int, Uint8List?> profilePictureBytesByUserId;
  final Map<int, String> linkedPersonIdsByUserId;
  final Map<int, String> linkedPersonNamesByUserId;
  final void Function(FamilyMember member, String displayName) onMemberTap;
  final VoidCallback onAddMember;
  final int remainingSlots;

  @override
  Widget build(BuildContext context) {
    final visibleMembers =
        members.where((member) => isAdmin || member.isActive).toList()
          ..sort(_compareMembers);
    final activeMembers = visibleMembers
        .where((member) => member.isActive)
        .toList();
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FamilyStorageCard(
          userDetails: userDetails,
          members: activeMembers,
          labelFor: _storageLabelFor,
          avatarColorFor: _avatarColorFor,
        ),
        const SizedBox(height: Spacing.xl),
        Text(l10n.members, style: TextStyles.h2),
        const SizedBox(height: Spacing.md),
        for (final (index, member) in visibleMembers.indexed) ...[
          _FamilyMemberRow(
            member: member,
            isCurrentUser: _isCurrentUser(member),
            isAdminView: isAdmin,
            displayName: _displayNameFor(member),
            profilePictureBytes: profilePictureBytesByUserId[member.userID],
            linkedPersonId: linkedPersonIdsByUserId[member.userID],
            hasSavedContact: contactsByUserId[member.userID] != null,
            avatarColor: _avatarColorFor(member),
            onTap: () => onMemberTap(member, _displayNameFor(member)),
          ),
          if (index < visibleMembers.length - 1)
            const SizedBox(height: Spacing.sm),
        ],
        if (isAdmin && remainingSlots > 0) ...[
          const SizedBox(height: Spacing.xl),
          ButtonComponent(
            label: l10n.addMember,
            leading: const HugeIcon(
              icon: HugeIcons.strokeRoundedUserAdd01,
              size: IconSizes.small,
              strokeWidth: 1.6,
            ),
            onTap: onAddMember,
          ),
        ],
      ],
    );
  }

  bool _isCurrentUser(FamilyMember member) =>
      member.email.trim().toLowerCase() ==
      userDetails.email.trim().toLowerCase();

  int _compareMembers(FamilyMember a, FamilyMember b) {
    if (_isCurrentUser(a)) return -1;
    if (_isCurrentUser(b)) return 1;
    if (isAdmin && a.isPending != b.isPending) {
      return a.isPending ? 1 : -1;
    }
    if (a.isAdmin != b.isAdmin) return a.isAdmin ? -1 : 1;

    final displayNameComparison = _displayNameFor(
      a,
    ).toLowerCase().compareTo(_displayNameFor(b).toLowerCase());
    return displayNameComparison != 0
        ? displayNameComparison
        : a.email.toLowerCase().compareTo(b.email.toLowerCase());
  }

  String _displayNameFor(FamilyMember member) =>
      _savedNameFor(member) ?? _linkedPersonNameFor(member) ?? member.email;

  String _storageLabelFor(FamilyMember member) =>
      _savedNameFor(member) ??
      _linkedPersonNameFor(member) ??
      member.email.split('@').first;

  String? _savedNameFor(FamilyMember member) {
    final savedName = contactsByUserId[member.userID]?.data?.name.trim();
    return savedName == null || savedName.isEmpty ? null : savedName;
  }

  String? _linkedPersonNameFor(FamilyMember member) {
    final personName = linkedPersonNamesByUserId[member.userID]?.trim();
    return personName == null || personName.isEmpty ? null : personName;
  }

  AvatarComponentColor _avatarColorFor(FamilyMember member) =>
      familyMemberAvatarComponentColor(member);
}

class _FamilyStorageCard extends StatelessWidget {
  const _FamilyStorageCard({
    required this.userDetails,
    required this.members,
    required this.labelFor,
    required this.avatarColorFor,
  });

  final UserDetails userDetails;
  final List<FamilyMember> members;
  final String Function(FamilyMember member) labelFor;
  final AvatarComponentColor Function(FamilyMember member) avatarColorFor;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final l10n = AppLocalizations.of(context);
    final totalStorage = userDetails.getTotalStorage();
    final totalUsed =
        userDetails.familyData?.getTotalUsage() ?? userDetails.usage;
    Color memberColor(FamilyMember member) =>
        avatarComponentColorValue(context, avatarColorFor(member));

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.fillLight,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Spacing.xl,
          vertical: Spacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(l10n.storage, style: TextStyles.h2)),
                Text(
                  l10n.storageUsedOfTotal(
                    used: convertBytesToReadableFormat(totalUsed),
                    total: convertBytesToReadableFormat(totalStorage),
                  ),
                  style: TextStyles.mini.copyWith(color: colors.textLight),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),
            _StorageBar(
              members: members,
              totalStorage: totalStorage,
              colorFor: memberColor,
            ),
            const SizedBox(height: Spacing.sm),
            Wrap(
              spacing: 10,
              runSpacing: Spacing.xs,
              children: [
                for (final member in members)
                  _StorageLegend(
                    color: memberColor(member),
                    label: labelFor(member),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StorageBar extends StatelessWidget {
  const _StorageBar({
    required this.members,
    required this.totalStorage,
    required this.colorFor,
  });

  final List<FamilyMember> members;
  final int totalStorage;
  final Color Function(FamilyMember member) colorFor;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return SizedBox(
      height: 5,
      child: LayoutBuilder(
        builder: (context, constraints) {
          var cumulativeUsage = 0;
          final segments = <Widget>[];
          for (final member in members) {
            cumulativeUsage += member.usage;
            final width = totalStorage <= 0
                ? 0.0
                : constraints.maxWidth * (cumulativeUsage / totalStorage);
            final visibleWidth = width.clamp(0.0, constraints.maxWidth);
            if (visibleWidth <= 0) {
              continue;
            }
            segments.add(
              Positioned(
                left: 0,
                child: Container(
                  width: visibleWidth,
                  height: 5,
                  decoration: BoxDecoration(
                    color: colorFor(member),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            );
          }

          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: colors.fillDark)),
                ...segments.reversed,
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StorageLegend extends StatelessWidget {
  const _StorageLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            label,
            style: TextStyles.tiny.copyWith(color: colors.textBase),
          ),
        ),
      ],
    );
  }
}

class _FamilyMemberRow extends StatelessWidget {
  const _FamilyMemberRow({
    required this.member,
    required this.isCurrentUser,
    required this.isAdminView,
    required this.displayName,
    required this.profilePictureBytes,
    required this.linkedPersonId,
    required this.hasSavedContact,
    required this.avatarColor,
    required this.onTap,
  });

  final FamilyMember member;
  final bool isCurrentUser;
  final bool isAdminView;
  final String displayName;
  final Uint8List? profilePictureBytes;
  final String? linkedPersonId;
  final bool hasSavedContact;
  final AvatarComponentColor avatarColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final actions = familyMemberActions(
      isAdmin: isAdminView,
      isCurrentUser: isCurrentUser,
      member: member,
      hasSavedContact: hasSavedContact,
    );
    final isInteractive = actions.isNotEmpty;
    final subtitle = member.isPending
        ? l10n.pending
        : l10n.memberStorageUsed(
            amount: convertBytesToReadableFormat(member.usage),
          );

    return MenuComponent(
      title: displayName,
      subtitle: subtitle,
      onTap: isInteractive ? onTap : null,
      leading: _MemberAvatar(
        member: member,
        displayName: displayName,
        profilePictureBytes: profilePictureBytes,
        linkedPersonId: linkedPersonId,
        avatarColor: avatarColor,
      ),
      trailing: isInteractive
          ? const Icon(Icons.chevron_right_rounded, size: IconSizes.medium)
          : null,
    );
  }
}

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({
    required this.member,
    required this.displayName,
    required this.profilePictureBytes,
    required this.linkedPersonId,
    required this.avatarColor,
  });

  final FamilyMember member;
  final String displayName;
  final Uint8List? profilePictureBytes;
  final String? linkedPersonId;
  final AvatarComponentColor avatarColor;

  @override
  Widget build(BuildContext context) {
    final cachedPixelWidth =
        (AvatarComponentSize.large.dimension *
                MediaQuery.devicePixelRatioOf(context))
            .round();
    final avatar = profilePictureBytes != null
        ? AvatarComponent.image(
            image: ResizeImage(
              MemoryImage(profilePictureBytes!),
              width: cachedPixelWidth,
            ),
            size: AvatarComponentSize.large,
            semanticLabel: displayName,
          )
        : linkedPersonId != null
        ? Semantics(
            image: true,
            label: displayName,
            child: SizedBox.square(
              dimension: AvatarComponentSize.large.dimension,
              child: ClipOval(
                child: PersonFaceWidget(
                  personId: linkedPersonId,
                  cachedPixelWidth: cachedPixelWidth,
                ),
              ),
            ),
          )
        : AvatarComponent(
            initials: _initials(displayName),
            color: avatarColor,
            size: AvatarComponentSize.large,
            semanticLabel: displayName,
          );

    if (!member.isAdmin) {
      return avatar;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -4,
          bottom: -4,
          child: Semantics(
            label: AppLocalizations.of(context).admin,
            child: ExcludeSemantics(
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedCrown02,
                color: context.componentColors.primary,
                size: IconSizes.small,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _initials(String value) {
  final words = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) {
    return '?';
  }
  if (words.length == 1) {
    return words.first.substring(0, 1);
  }
  return '${words.first.substring(0, 1)}${words.last.substring(0, 1)}';
}
