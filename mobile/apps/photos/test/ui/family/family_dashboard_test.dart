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
          librarySharingEnabled: true,
        ),
        [
          FamilyMemberAction.saveContact,
          FamilyMemberAction.shareAlbums,
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
          librarySharingEnabled: true,
        ),
        [FamilyMemberAction.editStorageLimit, FamilyMemberAction.removeMember],
      );
      expect(
        familyMemberActions(
          isAdmin: true,
          isCurrentUser: false,
          member: memberWithUserID,
          hasSavedContact: true,
          librarySharingEnabled: true,
        ),
        [
          FamilyMemberAction.editContact,
          FamilyMemberAction.shareAlbums,
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
            librarySharingEnabled: true,
          ),
          [FamilyMemberAction.editContact, FamilyMemberAction.shareAlbums],
        );
        expect(
          familyMemberActions(
            isAdmin: false,
            isCurrentUser: false,
            member: _member(userID: 42),
            hasSavedContact: false,
            librarySharingEnabled: true,
          ),
          [FamilyMemberAction.saveContact, FamilyMemberAction.shareAlbums],
        );
        expect(
          familyMemberActions(
            isAdmin: false,
            isCurrentUser: false,
            member: _member(),
            hasSavedContact: false,
            librarySharingEnabled: true,
          ),
          isEmpty,
        );
        expect(
          familyMemberActions(
            isAdmin: false,
            isCurrentUser: true,
            member: _member(userID: 42),
            hasSavedContact: true,
            librarySharingEnabled: true,
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
            librarySharingEnabled: true,
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
            librarySharingEnabled: true,
          ),
          [FamilyMemberAction.resendInvite, FamilyMemberAction.revokeInvite],
        );
      },
    );

    test('gates only library sharing actions behind its flag', () {
      final member = _member(userID: 42);

      expect(
        familyMemberActions(
          isAdmin: true,
          isCurrentUser: false,
          member: member,
          hasSavedContact: false,
          librarySharingEnabled: false,
        ),
        [
          FamilyMemberAction.saveContact,
          FamilyMemberAction.editStorageLimit,
          FamilyMemberAction.removeMember,
        ],
      );
      expect(
        familyMemberActions(
          isAdmin: false,
          isCurrentUser: false,
          member: member,
          hasSavedContact: true,
          librarySharingEnabled: false,
        ),
        [FamilyMemberAction.editContact],
      );
    });
  });

  group('familyMemberAvatarComponentColor', () {
    test('hashes every member including the current user', () {
      final currentUser = _member(email: 'admin@example.com', userID: 1);
      final otherMember = _member(email: 'saved@example.com', userID: 42);

      expect(
        familyMemberAvatarComponentColor(currentUser),
        avatarComponentColorForIdentity(
          avatarIdentityKey(
            email: currentUser.email,
            userID: currentUser.userID,
          ),
        ),
      );
      expect(
        familyMemberAvatarComponentColor(otherMember),
        avatarComponentColorForIdentity(
          avatarIdentityKey(
            email: otherMember.email,
            userID: otherMember.userID,
          ),
        ),
      );
    });
  });

  testWidgets('renders saved contacts without a storage legend at 375 pixels', (
    tester,
  ) async {
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
                librarySharingEnabled: true,
                sharedAlbumCountsByUserId: const {42: 5},
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
    expect(find.text('admin'), findsNothing);
    expect(find.text('Saved member'), findsOneWidget);
    expect(find.text('pending@example.com'), findsOneWidget);
    expect(find.textContaining('5 albums shared'), findsOneWidget);
    final avatars = tester
        .widgetList<AvatarComponent>(find.byType(AvatarComponent))
        .where((avatar) => avatar.image == null)
        .toList();
    expect(avatars, hasLength(3));
    expect(
      avatars.map((avatar) => avatar.color),
      everyElement(isIn(avatarComponentIdentityPalette)),
    );
    expect(avatars.map((avatar) => avatar.seed), everyElement(isNull));
    final currentUserAvatar = avatars.singleWhere(
      (avatar) => avatar.semanticLabel == 'admin@example.com',
    );
    expect(
      currentUserAvatar.color,
      familyMemberAvatarComponentColor(members.first),
    );
    final savedMemberAvatar = avatars.singleWhere(
      (avatar) => avatar.semanticLabel == 'Saved member',
    );
    expect(savedMemberAvatar.initials, 'SM');
    expect(
      savedMemberAvatar.color,
      avatarComponentColorForIdentity(
        avatarIdentityKey(email: savedMember.email, userID: savedMember.userID),
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
  });

  testWidgets('rings a linked Person face with its storage color for self', (
    tester,
  ) async {
    final member = _member(
      email: 'admin@example.com',
      userID: 42,
      status: FamilyMemberStatus.self,
    );
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
            librarySharingEnabled: false,
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
    final ringFinder = find.ancestor(
      of: find.byType(PersonFaceWidget),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is DecoratedBox &&
            widget.position == DecorationPosition.foreground &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).shape == BoxShape.circle,
      ),
    );
    expect(ringFinder, findsOneWidget);
    final ring = tester.widget<DecoratedBox>(ringFinder);
    final decoration = ring.decoration as BoxDecoration;
    final border = decoration.border! as Border;
    final avatarColor = familyMemberAvatarComponentColor(member);
    expect(
      border.top.color,
      avatarComponentColorValue(
        tester.element(find.byType(PersonFaceWidget)),
        avatarColor,
      ),
    );
  });

  testWidgets('does not report zero shared albums before counts are known', (
    tester,
  ) async {
    final currentUser = _member(
      email: 'admin@example.com',
      userID: 1,
      isAdmin: true,
      status: FamilyMemberStatus.self,
    );
    final otherMember = _member(email: 'member@example.com', userID: 42);
    final members = [currentUser, otherMember];

    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FamilyDashboard(
            userDetails: _userDetails(members),
            members: members,
            isAdmin: true,
            contactsByUserId: const {},
            profilePictureBytesByUserId: const {},
            linkedPersonIdsByUserId: const {},
            librarySharingEnabled: true,
            onMemberTap: (_) {},
            onAddMember: () {},
            remainingSlots: 3,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No albums shared'), findsNothing);
    expect(
      find.textContaining(RegExp('used', caseSensitive: false)),
      findsWidgets,
    );
  });

  testWidgets('hides shared-album counts when library sharing is disabled', (
    tester,
  ) async {
    final currentUser = _member(
      email: 'admin@example.com',
      userID: 1,
      isAdmin: true,
      status: FamilyMemberStatus.self,
    );
    final otherMember = _member(email: 'member@example.com', userID: 42);

    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FamilyDashboard(
            userDetails: _userDetails([currentUser, otherMember]),
            members: [currentUser, otherMember],
            isAdmin: true,
            contactsByUserId: const {},
            profilePictureBytesByUserId: const {},
            linkedPersonIdsByUserId: const {},
            librarySharingEnabled: false,
            sharedAlbumCountsByUserId: const {42: 5},
            onMemberTap: (_) {},
            onAddMember: () {},
            remainingSlots: 3,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('albums shared'), findsNothing);
    expect(
      find.textContaining(RegExp('used', caseSensitive: false)),
      findsWidgets,
    );
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
              librarySharingEnabled: false,
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
