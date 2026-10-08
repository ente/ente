import 'package:dio/dio.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:photos/core/configuration.dart';
import 'package:photos/core/event_bus.dart';
import 'package:photos/db/ml/base.dart';
import 'package:photos/ente_theme_data.dart';
import 'package:photos/events/contact_relationships_invalidated_event.dart';
import 'package:photos/models/collection/collection.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/services/collections_service.dart';
import 'package:photos/services/entity_service.dart';
import 'package:photos/services/machine_learning/face_ml/person/person_service.dart';
import 'package:photos/ui/sharing/share_collection_page.dart';
import 'package:photos/ui/sharing/widgets/participant_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'library_sharing_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      Configuration.userIDKey: 1,
      Configuration.emailKey: 'owner@example.com',
    });
    final preferences = await SharedPreferences.getInstance();
    ServiceLocator.instance.init(
      preferences,
      Dio(),
      Dio(),
      Dio(),
      PackageInfo(
        appName: 'Photos',
        packageName: 'photos',
        version: '1.0.0',
        buildNumber: '1',
      ),
    );
    try {
      await Configuration.instance.init(preferences);
    } on MissingPluginException {}
    PersonService.init(_FakeEntityService(), _FakeMLDataDB(), preferences);
  });

  setUp(() => CollectionsService.instance.collectionIDToCollections.clear());
  tearDown(() => CollectionsService.instance.collectionIDToCollections.clear());

  testWidgets('shows a recipient when library sharing finishes while open', (
    tester,
  ) async {
    final album = librarySharingTestAlbum(1);
    CollectionsService.instance.collectionIDToCollections[1] = album;
    await _showPage(tester, album);
    expect(find.text('friend@example.com'), findsNothing);

    _updateCachedAlbum(
      librarySharingTestAlbum(
        1,
        recipientRole: CollectionParticipantRole.viewer,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('friend@example.com'), findsOneWidget);
  });

  testWidgets('uses the current cache when sharing finishes before entry', (
    tester,
  ) async {
    final staleAlbum = librarySharingTestAlbum(1);
    CollectionsService.instance.collectionIDToCollections[1] =
        librarySharingTestAlbum(
          1,
          recipientRole: CollectionParticipantRole.viewer,
        );

    await _showPage(tester, staleAlbum);

    expect(find.text('friend@example.com'), findsOneWidget);
  });

  testWidgets('updates recipient roles and removals while open', (
    tester,
  ) async {
    final album = librarySharingTestAlbum(
      1,
      recipientRole: CollectionParticipantRole.viewer,
    );
    CollectionsService.instance.collectionIDToCollections[1] = album;
    await _showPage(tester, album);

    _updateCachedAlbum(
      librarySharingTestAlbum(
        1,
        recipientRole: CollectionParticipantRole.admin,
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<ParticipantRow>(find.byType(ParticipantRow)).role,
      CollectionParticipantRole.admin,
    );

    _updateCachedAlbum(librarySharingTestAlbum(1));
    await tester.pumpAndSettle();
    expect(find.text('friend@example.com'), findsNothing);
  });

  testWidgets('ignores other albums and stops listening after disposal', (
    tester,
  ) async {
    final album = librarySharingTestAlbum(
      1,
      recipientRole: CollectionParticipantRole.viewer,
    );
    CollectionsService.instance.collectionIDToCollections[1] = album;
    await _showPage(tester, album);
    final roster = tester.widget<ScrollableParticipantRoster>(
      find.byType(ScrollableParticipantRoster),
    );

    _updateCachedAlbum(librarySharingTestAlbum(2));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ScrollableParticipantRoster>(
        find.byType(ScrollableParticipantRoster),
      ),
      same(roster),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    _updateCachedAlbum(librarySharingTestAlbum(1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _showPage(WidgetTester tester, Collection album) async {
  await tester.binding.setSurfaceSize(const Size(402, 874));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: darkThemeData,
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      supportedLocales: StringsLocalizations.supportedLocales,
      home: ShareCollectionPage(album),
    ),
  );
  await tester.pumpAndSettle();
}

void _updateCachedAlbum(Collection album) {
  CollectionsService.instance.collectionIDToCollections[album.id] = album;
  Bus.instance.fire(ContactRelationshipsInvalidatedEvent());
}

class _FakeEntityService extends Fake implements EntityService {}

class _FakeMLDataDB extends Fake implements IMLDataDB<int> {}
