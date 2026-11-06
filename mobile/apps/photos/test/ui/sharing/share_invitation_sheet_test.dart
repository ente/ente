import "dart:async";

import "package:dio/dio.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:photos/ente_theme_data.dart";
import "package:photos/models/api/collection/user.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/ui/components/base_bottom_sheet.dart";
import "package:photos/ui/sharing/share_invitation_sheet.dart";

void main() {
  testWidgets("cancelling the extra-album confirmation makes no changes", (
    tester,
  ) async {
    var accepts = 0;
    var rejects = 0;
    await _launch(
      tester,
      getIDs: () => [10, 20],
      accept: (_) async {
        accepts++;
        return _album();
      },
      reject: () async => rejects++,
    );

    await tester.tap(find.text("Accept"));
    await _pumpSheetTransition(tester);
    expect(
      find.text("Other pending albums from Alice will also be accepted."),
      findsOneWidget,
    );
    await tester.tap(find.text("Cancel"));
    await tester.pumpAndSettle();
    expect(accepts, 0);
    expect(rejects, 0);
    expect(find.text("Accept invite?"), findsOneWidget);

    await tester.tap(find.text("Reject"));
    await tester.pumpAndSettle();
    expect(accepts, 0);
    expect(rejects, 1);
    expect(find.text("Accept invite?"), findsNothing);
  });

  testWidgets("accepts the captured batch and returns only after success", (
    tester,
  ) async {
    final pendingIDs = [10, 20];
    final accepted = Completer<Collection>();
    List<int>? suppliedIDs;
    Collection? result;
    await _launch(
      tester,
      getIDs: () => pendingIDs,
      accept: (ids) {
        suppliedIDs = ids;
        return accepted.future;
      },
      onResult: (collection) => result = collection,
    );

    await tester.tap(find.text("Accept"));
    await _pumpSheetTransition(tester);
    pendingIDs.add(30);
    await tester.tap(find.text("Accept").last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(suppliedIDs, [10, 20]);
    expect(result, isNull);

    final collection = _album();
    accepted.complete(collection);
    await tester.pumpAndSettle();
    expect(result, same(collection));
    expect(find.text("Accept invite?"), findsNothing);
  });

  testWidgets("a failed single acceptance keeps the request for retry", (
    tester,
  ) async {
    final collection = _album();
    Collection? result;
    var attempts = 0;
    await _launch(
      tester,
      getIDs: () => [10],
      accept: (ids) async {
        expect(ids, [10]);
        attempts++;
        if (attempts == 1) {
          throw DioException(
            requestOptions: RequestOptions(),
            type: DioExceptionType.connectionError,
            error: "SocketException",
          );
        }
        return collection;
      },
      onResult: (collection) => result = collection,
    );

    await tester.tap(find.text("Accept"));
    await _pumpSheetTransition(tester);
    expect(attempts, 1);
    expect(result, isNull);
    expect(find.text("Error"), findsOneWidget);
    expect(
      find.text("Other pending albums from Alice will also be accepted."),
      findsNothing,
    );
    await tester.tap(find.byType(BottomSheetCloseButton));
    await tester.pumpAndSettle();
    expect(find.text("Accept invite?"), findsOneWidget);

    await tester.tap(find.text("Accept"));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(result, same(collection));
    expect(find.text("Accept invite?"), findsNothing);
  });
}

Future<void> _pumpSheetTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _launch(
  WidgetTester tester, {
  required List<int> Function() getIDs,
  required Future<Collection> Function(List<int>) accept,
  Future<void> Function()? reject,
  void Function(Collection?)? onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: lightThemeData,
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      supportedLocales: StringsLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              final result = await showShareInvitationSheet(
                context: context,
                inviterName: "Alice",
                albumName: "Summer",
                getAcceptanceIDs: getIDs,
                onAccept: accept,
                onReject: reject ?? () async {},
              );
              onResult?.call(result);
            },
            child: const Text("Open invite"),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text("Open invite"));
  await tester.pumpAndSettle();
}

Collection _album() => Collection(
  10,
  User(id: 1, email: "alice@example.com"),
  "",
  null,
  "Summer",
  null,
  null,
  CollectionType.album,
  CollectionAttributes(),
  [],
  [],
  1,
);
