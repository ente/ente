import 'package:ente_components/ente_components.dart';
import 'package:ente_contacts/contacts.dart' as contacts;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photos/ente_theme_data.dart';
import 'package:photos/gateways/billing/models/subscription.dart';
import 'package:photos/gateways/storage_bonus/models/bonus.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:photos/models/user_details.dart';
import 'package:photos/ui/family/family_dashboard.dart';
import 'package:photos/ui/viewer/people/person_face_widget.dart';

void main() {
  testWidgets(
    'renders saved contacts and their shared-album counts at 375 pixels',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(375, 812));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();

      final savedMember = _member(email: 'saved@example.com', userID: 42);
      final pendingMember = _member(
        email: 'pending@example.com',
        status: FamilyMemberStatus.invited,
      );
      final currentUser = _member(
        email: 'admin@example.com',
        userID: 1,
        isAdmin: true,
        status: FamilyMemberStatus.self,
      );
      final members = [currentUser, savedMember, pendingMember];
      FamilyMember? selectedMember;

      await tester.pumpWidget(
        MaterialApp(
          theme: lightThemeData,
          localizationsDelegates: StringsLocalizations.localizationsDelegates,
          supportedLocales: StringsLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FamilyDashboard(
                  userDetails: _userDetails(members),
                  members: members,
                  isAdmin: true,
                  contactsByUserId: {
                    1: _contact(currentUser, name: 'Current user'),
                    42: _contact(savedMember, name: 'Saved member'),
                  },
                  profilePictureBytesByUserId: const {},
                  linkedPersonIdsByUserId: const {},
                  linkedPersonNamesByUserId: const {
                    1: 'Person current user',
                    42: 'Person saved member',
                  },
                  librarySharingEnabled: true,
                  sharedAlbumCountsByUserId: const {42: 5},
                  onMemberTap: (member, _) => selectedMember = member,
                  onAddMember: () {},
                  remainingSlots: 2,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Current user'), findsWidgets);
      expect(find.text('Saved member'), findsNWidgets(2));
      expect(find.text('pending@example.com'), findsOneWidget);
      expect(find.textContaining('5 albums shared'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'Admin')), findsOneWidget);
      semantics.dispose();

      await tester.tap(find.byType(MenuComponent).at(1));
      expect(selectedMember, same(savedMember));
    },
  );

  testWidgets('uses a linked Person name and face without a saved contact', (
    tester,
  ) async {
    final member = _member(email: 'member@example.com', userID: 42);
    final members = [member];
    String? selectedDisplayName;

    await tester.pumpWidget(
      MaterialApp(
        theme: lightThemeData,
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: StringsLocalizations.supportedLocales,
        home: Scaffold(
          body: FamilyDashboard(
            userDetails: _userDetails(members),
            members: members,
            isAdmin: false,
            contactsByUserId: const {},
            profilePictureBytesByUserId: const {},
            linkedPersonIdsByUserId: const {42: 'person-42'},
            linkedPersonNamesByUserId: const {42: 'Current person'},
            onMemberTap: (_, displayName) {
              selectedDisplayName = displayName;
            },
            onAddMember: () {},
            remainingSlots: 0,
          ),
        ),
      ),
    );

    expect(find.text('Current person'), findsWidgets);
    expect(find.byType(PersonFaceWidget), findsOneWidget);
    final personAvatar = tester.widget<PersonFaceWidget>(
      find.byType(PersonFaceWidget),
    );
    expect(personAvatar.personId, 'person-42');

    await tester.tap(find.byType(MenuComponent));
    expect(selectedDisplayName, 'Current person');
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
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: StringsLocalizations.supportedLocales,
        home: Scaffold(
          body: FamilyDashboard(
            userDetails: _userDetails(members),
            members: members,
            isAdmin: true,
            contactsByUserId: const {},
            profilePictureBytesByUserId: const {},
            linkedPersonIdsByUserId: const {},
            linkedPersonNamesByUserId: const {},
            librarySharingEnabled: true,
            onMemberTap: (_, _) {},
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
        localizationsDelegates: StringsLocalizations.localizationsDelegates,
        supportedLocales: StringsLocalizations.supportedLocales,
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
              linkedPersonNamesByUserId: const {4: 'Aaron'},
              onMemberTap: (_, _) {},
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
      ['admin@example.com', 'Aaron', 'Amy', 'Zoe'],
    );
  });
}

contacts.ContactRecord _contact(FamilyMember member, {required String name}) {
  return contacts.ContactRecord(
    id: 'contact-${member.userID}',
    contactUserId: member.userID!,
    email: member.email,
    name: name,
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
