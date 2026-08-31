import 'package:dio/dio.dart';
import 'package:ente_components/ente_components.dart';
import 'package:ente_strings/ente_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_easyloading/flutter_easyloading.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:photos/app_mode.dart';
import 'package:photos/ente_theme_data.dart';
import 'package:photos/models/file/file.dart';
import 'package:photos/models/file/file_type.dart';
import 'package:photos/models/file/trash_file.dart';
import 'package:photos/models/files_split.dart';
import 'package:photos/models/selected_files.dart';
import 'package:photos/service_locator.dart';
import 'package:photos/settings/local_settings.dart';
import 'package:photos/utils/delete_file_util.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    ServiceLocator.instance.init(
      prefs,
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
  });

  setUp(() async {
    await localSettings.setAppMode(AppMode.enteGallery);
    await localSettings.setDeletePreference(null);
  });

  group('deleteFromTrash', () {
    testWidgets('uses the migrated warning delete sheet', (tester) async {
      final file = EnteTrashFile.from(
        _file(generatedID: 21, uploadedID: 31),
        deleteBy: 0,
        createdAt: 0,
        updateAt: 0,
      );
      bool? result;

      await tester.pumpWidget(
        _TestApp(
          onOpen: (context) async {
            result = await deleteFromEnteTrash(context, [file]);
          },
        ),
      );

      await tester.tap(find.text('Open delete sheet'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheetComponent), findsOneWidget);
      _expectDeleteWarningIllustration();
      expect(find.text('Are you sure?'), findsOneWidget);
      expect(
        find.text(
          'Selected items will be permanently deleted and cannot be recovered.',
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      _expectVisibleButtonsInOrder(tester, ['Yes, delete']);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(result, false);
    });
  });

  group('showDeleteSheet', () {
    testWidgets('mixed delete sheet with saved default starts collapsed', (
      tester,
    ) async {
      await localSettings.setDeletePreference(DeletePreference.DeleteFromBoth);
      final file = _file(generatedID: 22, uploadedID: 32, localID: 'local-22');
      final selectedFiles = SelectedFiles()..selectAll({file});

      await _pumpDeleteSheet(
        tester,
        selectedFiles: selectedFiles,
        split: FilesSplit(
          pendingUploads: const [],
          ownedByCurrentUser: [file],
          ownedByOtherUsers: const [],
        ),
      );

      expect(find.byType(ButtonComponent), findsOneWidget);
      expect(find.text('Delete from both'), findsOneWidget);
      expect(find.text('More options'), findsOneWidget);
      expect(find.text('Set as my default choice'), findsNothing);
    });

    testWidgets('cancel keeps the selection', (tester) async {
      final file = _file(generatedID: 4, uploadedID: 14);
      final selectedFiles = SelectedFiles()..selectAll({file});

      await _pumpDeleteSheet(
        tester,
        selectedFiles: selectedFiles,
        split: FilesSplit(
          pendingUploads: const [],
          ownedByCurrentUser: [file],
          ownedByOtherUsers: const [],
        ),
      );

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheetComponent), findsNothing);
      expect(selectedFiles.files, contains(file));
    });

    testWidgets(
      'remote delete action uses the legacy remote delete path and clears selection',
      (tester) async {
        final file = _file(generatedID: 7, uploadedID: 17);
        final selectedFiles = SelectedFiles()..selectAll({file});
        var remoteDeleteCalls = 0;
        List<EnteFile>? remoteDeleteFiles;

        await _pumpDeleteSheet(
          tester,
          selectedFiles: selectedFiles,
          split: FilesSplit(
            pendingUploads: const [],
            ownedByCurrentUser: [file],
            ownedByOtherUsers: const [],
          ),
          deleteFromRemoteOnlyOverride: (context, files) async {
            remoteDeleteCalls++;
            remoteDeleteFiles = List.of(files);
          },
        );

        await tester.tap(find.text('Delete from Ente'));
        await tester.pumpAndSettle();

        expect(remoteDeleteCalls, 1);
        expect(remoteDeleteFiles, [file]);
        expect(find.byType(BottomSheetComponent), findsNothing);
        expect(selectedFiles.files, isEmpty);

        await _settleToast(tester);
      },
    );

    testWidgets(
      'device delete action uses the legacy device delete path and clears selection',
      (tester) async {
        final file = _file(generatedID: 8, localID: 'local-8');
        final selectedFiles = SelectedFiles()..selectAll({file});
        var deviceDeleteCalls = 0;
        List<EnteFile>? deviceDeleteFiles;

        await _pumpDeleteSheet(
          tester,
          selectedFiles: selectedFiles,
          split: FilesSplit(
            pendingUploads: [file],
            ownedByCurrentUser: const [],
            ownedByOtherUsers: const [],
          ),
          deleteOnDeviceOnlyOverride: (context, files) async {
            deviceDeleteCalls++;
            deviceDeleteFiles = List.of(files);
          },
        );

        await tester.tap(find.text('Delete from device'));
        await tester.pumpAndSettle();

        expect(deviceDeleteCalls, 1);
        expect(deviceDeleteFiles, [file]);
        expect(find.byType(BottomSheetComponent), findsNothing);
        expect(selectedFiles.files, isEmpty);
      },
    );

    testWidgets(
      'delete from both uses the legacy everywhere delete path and clears selection',
      (tester) async {
        final file = _file(generatedID: 9, uploadedID: 19, localID: 'local-9');
        final selectedFiles = SelectedFiles()..selectAll({file});
        var everywhereDeleteCalls = 0;
        List<EnteFile>? everywhereDeleteFiles;

        await _pumpDeleteSheet(
          tester,
          selectedFiles: selectedFiles,
          split: FilesSplit(
            pendingUploads: const [],
            ownedByCurrentUser: [file],
            ownedByOtherUsers: const [],
          ),
          deleteFromEverywhereOverride: (context, files) async {
            everywhereDeleteCalls++;
            everywhereDeleteFiles = List.of(files);
          },
        );

        await tester.tap(find.text('Delete from both'));
        await tester.pumpAndSettle();

        expect(everywhereDeleteCalls, 1);
        expect(everywhereDeleteFiles, [file]);
        expect(find.byType(BottomSheetComponent), findsNothing);
        expect(selectedFiles.files, isEmpty);
      },
    );

    testWidgets('only other-user files keep the legacy no-sheet behavior', (
      tester,
    ) async {
      final file = _file(generatedID: 6, uploadedID: 16, ownerID: 2);
      final selectedFiles = SelectedFiles()..selectAll({file});

      await _pumpDeleteSheet(
        tester,
        selectedFiles: selectedFiles,
        split: FilesSplit(
          pendingUploads: const [],
          ownedByCurrentUser: const [],
          ownedByOtherUsers: [file],
        ),
      );

      expect(find.byType(BottomSheetComponent), findsNothing);
      expect(selectedFiles.files, contains(file));

      await _settleToast(tester);
    });

    testWidgets(
      'local gallery mode deletes device files without showing a confirmation sheet',
      (tester) async {
        await localSettings.setAppMode(AppMode.localGallery);
        final file = _file(generatedID: 10, localID: 'local-10');
        final selectedFiles = SelectedFiles()..selectAll({file});
        var deviceDeleteCalls = 0;
        List<EnteFile>? deviceDeleteFiles;

        await _pumpDeleteSheet(
          tester,
          selectedFiles: selectedFiles,
          split: FilesSplit(
            pendingUploads: [file],
            ownedByCurrentUser: const [],
            ownedByOtherUsers: const [],
          ),
          deleteOnDeviceOnlyOverride: (context, files) async {
            deviceDeleteCalls++;
            deviceDeleteFiles = List.of(files);
          },
        );

        expect(find.byType(BottomSheetComponent), findsNothing);
        expect(deviceDeleteCalls, 1);
        expect(deviceDeleteFiles, [file]);
        expect(selectedFiles.files, isEmpty);
      },
    );

    testWidgets(
      'local gallery mode with no device files keeps the legacy no-sheet behavior',
      (tester) async {
        await localSettings.setAppMode(AppMode.localGallery);
        final file = _file(generatedID: 11, uploadedID: 21);
        final selectedFiles = SelectedFiles()..selectAll({file});
        var deviceDeleteCalls = 0;

        await _pumpDeleteSheet(
          tester,
          selectedFiles: selectedFiles,
          split: FilesSplit(
            pendingUploads: const [],
            ownedByCurrentUser: [file],
            ownedByOtherUsers: const [],
          ),
          deleteOnDeviceOnlyOverride: (context, files) async {
            deviceDeleteCalls++;
          },
        );

        expect(find.byType(BottomSheetComponent), findsNothing);
        expect(deviceDeleteCalls, 0);
        expect(selectedFiles.files, contains(file));

        await _settleToast(tester);
      },
    );
  });
}

Future<void> _pumpDeleteSheet(
  WidgetTester tester, {
  required SelectedFiles selectedFiles,
  required FilesSplit split,
  Future<void> Function(BuildContext context, List<EnteFile> files)?
  deleteFromRemoteOnlyOverride,
  Future<void> Function(BuildContext context, List<EnteFile> files)?
  deleteOnDeviceOnlyOverride,
  Future<void> Function(BuildContext context, List<EnteFile> files)?
  deleteFromEverywhereOverride,
}) async {
  await tester.pumpWidget(
    _TestApp(
      onOpen: (context) async {
        await showDeleteSheet(
          context,
          selectedFiles,
          split,
          deleteFromRemoteOnlyOverride: deleteFromRemoteOnlyOverride,
          deleteOnDeviceOnlyOverride: deleteOnDeviceOnlyOverride,
          deleteFromEverywhereOverride: deleteFromEverywhereOverride,
        );
      },
    ),
  );

  await tester.tap(find.text('Open delete sheet'));
  await tester.pumpAndSettle();
}

EnteFile _file({
  required int generatedID,
  int? uploadedID,
  int ownerID = 1,
  String? localID,
  FileType fileType = FileType.image,
}) {
  return EnteFile()
    ..generatedID = generatedID
    ..uploadedFileID = uploadedID
    ..ownerID = ownerID
    ..collectionID = uploadedID == null ? null : 100
    ..localID = localID
    ..fileType = fileType;
}

Future<void> _settleToast(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void _expectVisibleButtonsInOrder(WidgetTester tester, List<String> labels) {
  for (final label in labels) {
    expect(find.text(label), findsOneWidget);
  }

  for (var i = 0; i < labels.length - 1; i++) {
    final firstTop = tester.getTopLeft(find.text(labels[i])).dy;
    final secondTop = tester.getTopLeft(find.text(labels[i + 1])).dy;
    expect(
      firstTop,
      lessThan(secondTop),
      reason: '${labels[i]} should appear above ${labels[i + 1]}',
    );
  }
}

void _expectDeleteWarningIllustration([
  String assetName = 'assets/warning-red.png',
]) {
  expect(
    find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName == assetName,
    ),
    findsOneWidget,
  );
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.onOpen});

  final Future<void> Function(BuildContext context) onOpen;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: darkThemeData,
      localizationsDelegates: StringsLocalizations.localizationsDelegates,
      supportedLocales: StringsLocalizations.supportedLocales,
      builder: EasyLoading.init(),
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                await onOpen(context);
              },
              child: const Text('Open delete sheet'),
            );
          },
        ),
      ),
    );
  }
}
