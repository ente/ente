import 'package:ente_components/ente_components.dart';
import 'package:ente_contacts/contacts.dart' as contacts;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:photos/ente_theme_data.dart';
import 'package:photos/gateways/billing/models/subscription.dart';
import 'package:photos/gateways/storage_bonus/models/bonus.dart';
import 'package:photos/generated/l10n.dart';
import 'package:photos/models/user_details.dart';
import 'package:photos/ui/family/family_dashboard.dart';
import 'package:photos/ui/viewer/people/person_face_widget.dart';
import 'package:photos/utils/avatar_util.dart';

void main() {
  group('familyMemberActions', () {
    test('gates admin contact actions on user ID for active members', () {
      final memberWithUserID = _member(userID: 42);
      final memberWithoutUserID = _member();

      expect(
        familyMemberActions(
          isAdmin: true,
          isCurrentUser: false,
          member: memberWithUserID,
          hasSavedContact: false,
        ),
        [
          FamilyMemberAction.saveContact,
          FamilyMemberAction.editStorageLimit,
          FamilyMemberAction.removeMember,
        ],
      );
      expect(
        familyMemberActions(
          isAdmin: true,
          isCurrentUser: false,
          member: memberWithoutUserID,
          hasSavedContact: false,
        ),
        [FamilyMemberAction.editStorageLimit, FamilyMemberAction.removeMember],
      );
      expect(
        familyMemberActions(
          isAdmin: true,
          isCurrentUser: false,
          member: memberWithUserID,
          hasSavedContact: true,
        ),
        [
          FamilyMemberAction.editContact,
          FamilyMemberAction.editStorageLimit,
          FamilyMemberAction.removeMember,
        ],
      );
    });

    test(
      'lets members manage contacts only for other members with user IDs',
      () {
        expect(
          familyMemberActions(
            isAdmin: false,
            isCurrentUser: false,
            member: _member(userID: 42),
            hasSavedContact: true,
          ),
          [FamilyMemberAction.editContact],
        );
        expect(
          familyMemberActions(
            isAdmin: false,
            isCurrentUser: false,
            member: _member(userID: 42),
            hasSavedContact: false,
          ),
          [FamilyMemberAction.saveContact],
        );
        expect(
          familyMemberActions(
            isAdmin: false,
            isCurrentUser: false,
            member: _member(),
            hasSavedContact: false,
          ),
          isEmpty,
        );
        expect(
          familyMemberActions(
            isAdmin: false,
            isCurrentUser: true,
            member: _member(userID: 42),
            hasSavedContact: true,
          ),
          isEmpty,
        );
      },
    );

    test(
      'keeps pending-invite management while honoring provisioned user IDs',
      () {
        expect(
          familyMemberActions(
            isAdmin: true,
            isCurrentUser: false,
            member: _member(status: FamilyMemberStatus.invited, userID: 42),
            hasSavedContact: true,
          ),
          [
            FamilyMemberAction.editContact,
            FamilyMemberAction.resendInvite,
            FamilyMemberAction.revokeInvite,
          ],
        );
        expect(
          familyMemberActions(
            isAdmin: true,
            isCurrentUser: false,
            member: _member(status: FamilyMemberStatus.invited),
            hasSavedContact: false,
          ),
          [FamilyMemberAction.resendInvite, FamilyMemberAction.revokeInvite],
        );
      },
    );
  });

  group('familyMemberAvatarComponentColor', () {
    test('uses black for the current user and hashes other members', () {
      final currentUser = _member(email: 'admin@example.com', userID: 1);
      final otherMember = _member(email: 'saved@example.com', userID: 42);

      expect(
        familyMemberAvatarComponentColor(
          currentUser,
          currentUserEmail: 'ADMIN@example.com',
        ),
        AvatarComponentColor.black,
      );
      expect(
        familyMemberAvatarComponentColor(
          otherMember,
          currentUserEmail: currentUser.email,
        ),
        avatarComponentColorForIdentity(
          avatarIdentityKey(
            email: otherMember.email,
            userID: otherMember.userID,
          ),
        ),
      );
    });
  });

  testWidgets(
    'renders saved contacts and no shared-album content at 375 pixels',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 812));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();

      final savedMember = _member(email: 'saved@example.com', userID: 42);
      final pendingMember = _member(
        email: 'pending@example.com',
        status: FamilyMemberStatus.invited,
      );
      final members = [
        _member(
          email: 'admin@example.com',
          userID: 1,
          isAdmin: true,
          status: FamilyMemberStatus.self,
        ),
        savedMember,
        pendingMember,
      ];
      FamilyMember? selectedMember;

      await tester.pumpWidget(
        MaterialApp(
          theme: lightThemeData,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FamilyDashboard(
                  userDetails: _userDetails(members),
                  members: members,
                  isAdmin: true,
                  contactsByUserId: {
                    42: _contact(savedMember, name: 'Saved member'),
                  },
                  profilePictureBytesByUserId: const {},
                  linkedPersonIdsByUserId: const {},
                  onMemberTap: (member) => selectedMember = member,
                  onAddMember: () {},
                  remainingSlots: 2,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('admin@example.com'), findsOneWidget);
      expect(find.text('admin'), findsOneWidget);
      expect(find.text('Saved member'), findsNWidgets(2));
      expect(find.text('pending@example.com'), findsOneWidget);
      expect(
        find.textContaining(RegExp('shared album', caseSensitive: false)),
        findsNothing,
      );
      final avatars = tester
          .widgetList<AvatarComponent>(find.byType(AvatarComponent))
          .where((avatar) => avatar.image == null)
          .toList();
      expect(avatars, hasLength(3));
      expect(
        avatars.map((avatar) => avatar.color),
        everyElement(
          isIn(const [
            AvatarComponentColor.yellow,
            AvatarComponentColor.green,
            AvatarComponentColor.orange,
            AvatarComponentColor.pink,
            AvatarComponentColor.purple,
            AvatarComponentColor.blue,
            AvatarComponentColor.cyan,
            AvatarComponentColor.black,
          ]),
        ),
      );
      expect(avatars.map((avatar) => avatar.seed), everyElement(isNull));
      final currentUserAvatar = avatars.singleWhere(
        (avatar) => avatar.semanticLabel == 'admin@example.com',
      );
      expect(currentUserAvatar.color, AvatarComponentColor.black);
      final savedMemberAvatar = avatars.singleWhere(
        (avatar) => avatar.semanticLabel == 'Saved member',
      );
      expect(
        savedMemberAvatar.color,
        avatarComponentColorForIdentity(
          avatarIdentityKey(
            email: savedMember.email,
            userID: savedMember.userID,
          ),
        ),
      );
      final crown = tester
          .widgetList<HugeIcon>(find.byType(HugeIcon))
          .singleWhere(
            (icon) => identical(icon.icon, HugeIcons.strokeRoundedCrown02),
          );
      expect(crown.icon, HugeIcons.strokeRoundedCrown02);
      expect(find.bySemanticsLabel(RegExp(r'Admin')), findsOneWidget);
      semantics.dispose();

      await tester.tap(find.byType(MenuComponent).at(1));
      expect(selectedMember, same(savedMember));
    },
  );

  testWidgets('uses a linked Person face when no contact photo is saved', (
    tester,
  ) async {
    final member = _member(email: 'me@example.com', userID: 42);
    final members = [member];

    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FamilyDashboard(
            userDetails: _userDetails(members),
            members: members,
            isAdmin: false,
            contactsByUserId: const {},
            profilePictureBytesByUserId: const {},
            linkedPersonIdsByUserId: const {42: 'person-42'},
            onMemberTap: (_) {},
            onAddMember: () {},
            remainingSlots: 0,
          ),
        ),
      ),
    );

    expect(find.byType(PersonFaceWidget), findsOneWidget);
    final personAvatar = tester.widget<PersonFaceWidget>(
      find.byType(PersonFaceWidget),
    );
    expect(personAvatar.personId, 'person-42');
  });

  testWidgets('sorts other members by their displayed name or email', (
    tester,
  ) async {
    final currentUser = _member(
      email: 'admin@example.com',
      userID: 1,
      isAdmin: true,
      status: FamilyMemberStatus.self,
    );
    final zoe = _member(email: 'a@example.com', userID: 2);
    final amy = _member(email: 'z@example.com', userID: 3);
    final bob = _member(email: 'bob@example.com', userID: 4);
    final members = [currentUser, zoe, amy, bob];

    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: FamilyDashboard(
              userDetails: _userDetails(members),
              members: members,
              isAdmin: true,
              contactsByUserId: {
                2: _contact(zoe, name: 'Zoe'),
                3: _contact(amy, name: 'Amy'),
              },
              profilePictureBytesByUserId: const {},
              linkedPersonIdsByUserId: const {},
              onMemberTap: (_) {},
              onAddMember: () {},
              remainingSlots: 0,
            ),
          ),
        ),
      ),
    );

    expect(
      tester
          .widgetList<MenuComponent>(find.byType(MenuComponent))
          .map((item) => item.title),
      ['admin@example.com', 'Amy', 'bob@example.com', 'Zoe'],
    );
  });
}

contacts.ContactRecord _contact(FamilyMember member, {required String name}) {
  return contacts.ContactRecord(
    id: 'contact-${member.userID}',
    contactUserId: member.userID!,
    email: member.email,
    data: contacts.ContactData(contactUserId: member.userID!, name: name),
    profilePictureAttachmentId: null,
    isDeleted: false,
    createdAt: 1,
    updatedAt: 1,
  );
}

FamilyMember _member({
  String email = 'member@example.com',
  FamilyMemberStatus status = FamilyMemberStatus.accepted,
  int? userID,
  bool isAdmin = false,
}) {
  return FamilyMember(
    email,
    1024,
    'family-member',
    userID,
    isAdmin,
    status,
    null,
  );
}

UserDetails _userDetails(List<FamilyMember> members) {
  return UserDetails(
    'admin@example.com',
    1024,
    0,
    0,
    0,
    Subscription(
      productID: 'family',
      storage: 20 * 1024 * 1024 * 1024,
      originalTransactionID: '',
      paymentProvider: '',
      expiryTime: 0,
      price: '',
      period: 'month',
    ),
    FamilyData(members, 20 * 1024 * 1024 * 1024, 0, 0),
    ProfileData(),
    BonusData([]),
  );
}
